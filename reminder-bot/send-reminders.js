// Runs on a GitHub Actions cron schedule (see .github/workflows/send-reminders.yml).
// For every user, checks their tasks in Firestore for any reminder offset
// whose time has come due and hasn't fired yet, sends a push notification
// to that user's registered devices via Firebase Cloud Messaging, and
// marks it as fired in Firestore — which then syncs back down to every
// device automatically (same mechanism as the rest of task sync), so the
// app's "🔔 fired/total" display stays accurate everywhere.

const admin = require('firebase-admin');

const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
if (!serviceAccountJson) {
  console.error('Missing FIREBASE_SERVICE_ACCOUNT_JSON environment variable.');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(serviceAccountJson)),
});

const db = admin.firestore();
const messaging = admin.messaging();

function offsetLabel(minutes) {
  if (minutes === 0) return 'At due time';
  if (minutes < 60) return `${minutes} min before`;
  if (minutes < 1440) return `${Math.round(minutes / 60)} hour(s) before`;
  return `${Math.round(minutes / 1440)} day(s) before`;
}

async function main() {
  const now = Date.now();
  const usersSnap = await db.collection('users').get();
  let sentCount = 0;

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const tasksSnap = await db
      .collection('users')
      .doc(uid)
      .collection('tasks')
      .where('isComplete', '==', false)
      .get();

    for (const taskDoc of tasksSnap.docs) {
      const task = taskDoc.data();
      const offsets = task.reminderOffsetsMinutes || [];
      if (!task.dueDate || offsets.length === 0) continue;

      const dueMs = new Date(task.dueDate).getTime();
      const fired = new Set(task.firedOffsetsMinutes || []);
      const newlyDue = offsets.filter((m) => {
        if (fired.has(m)) return false;
        return dueMs - m * 60000 <= now;
      });

      if (newlyDue.length === 0) continue;

      const tokensSnap = await db
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .get();
      const tokens = tokensSnap.docs.map((d) => d.id);

      if (tokens.length > 0) {
        const label =
          newlyDue.length === 1
            ? offsetLabel(newlyDue[0])
            : `${newlyDue.length} reminders due`;
        const body = task.notes ? `${label} — ${task.notes}` : label;

        try {
          const response = await messaging.sendEachForMulticast({
            tokens,
            notification: { title: task.title, body },
          });
          sentCount += response.successCount;
          if (response.failureCount > 0) {
            response.responses.forEach((r, i) => {
              if (!r.success) {
                console.warn(`Failed to send to token ${tokens[i]}:`, r.error?.message);
              }
            });
          }
        } catch (err) {
          console.error(`FCM send failed for user ${uid}, task ${taskDoc.id}:`, err);
        }
      } else {
        console.log(`User ${uid} has no registered devices — skipping push, marking fired anyway.`);
      }

      // Mark fired regardless of delivery success, so a bad token
      // doesn't cause the same reminder to retry forever.
      await taskDoc.ref.update({
        firedOffsetsMinutes: admin.firestore.FieldValue.arrayUnion(...newlyDue),
      });
    }
  }

  console.log(`Done. Sent ${sentCount} notification(s).`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });

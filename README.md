# To-Do App (Flutter)

Cross-platform to-do app with main tasks, subtasks, multiple reminders per
task, and a pin-to-corner mini window on desktop. Runs on Android, Windows,
macOS, and Linux from one codebase.

Out of the box it works **fully offline** using local storage (Hive).
See the bottom of this file to turn on **cross-device cloud sync** via Firebase.

---

## 1. Install Flutter

Download the Flutter SDK: https://docs.flutter.dev/get-started/install
Then verify your setup:

```bash
flutter doctor
```

Fix anything it flags (Android SDK, Visual Studio for Windows desktop, etc).
For Windows desktop specifically, in Visual Studio Installer make sure the
**"Desktop development with C++"** workload is checked.

Enable desktop support if not already on:

```bash
flutter config --enable-windows-desktop   # or --enable-linux-desktop / --enable-macos-desktop
```

## 2. Get dependencies

From the `todo_app` folder:

```bash
flutter pub get
```

## 3. Run it

**Before running, fully close any previous instance of the app** (window and
terminal) — a stale instance can make it look like your latest changes
didn't take effect.

```bash
flutter devices          # see what's available
flutter run -d windows   # or: -d linux, -d macos, -d chrome, or an Android device id
```

For Android, plug in a device (USB debugging on) or start an emulator, then:

```bash
flutter run -d android
```

## 4. Build a release app

```bash
flutter build apk           # Android — installable .apk, no USB debugging needed
flutter build windows       # Windows
flutter build macos         # macOS
flutter build linux         # Linux
```

The Windows `.exe` ends up at `build\windows\x64\runner\Release\todo_app.exe` — copy that (or the whole `Release` folder) anywhere and double-click to run it like a normal installed app.

---

## Features

### Main tasks & subtasks
Tap **+ New task** to add a main task. Expand a task (arrow on the right) to
see or add its subtasks. Each task or subtask has its own optional due date,
notes, and reminders. Edit or delete either one via the ⋮ menu.

### Due dates & reminders
Set a **due date & time** on a task, then pick **as many reminder chips as
you want** — "At due time," "10 min before," "1 hour before," "2 hours
before," "1 day before," or **Custom** for any other offset (e.g. "3 days, 4
hours before"). Every reminder you pick fires separately, so you can be
reminded a day ahead *and* an hour ahead *and* right at the deadline.
Reminders are stored as offsets from the due date, so editing the due date
later moves every reminder along with it automatically.

The task list shows a summary (📅 due date, 🔔 reminder count) on both main
tasks and subtasks so you can confirm what's set at a glance.

**Reminder setup you need to do once** — see the dedicated section below.

### Mini window (Windows/macOS/Linux only)
Click the picture-in-picture icon in the app bar to shrink the window into a
small, always-on-top checklist pinned to the bottom-right corner of your
screen — handy for keeping it visible while you work. Click the expand icon
inside it to restore the full window. This has no effect on Android (phone
apps don't really have "windows" to shrink).

---

## Reminders — one-time setup needed

**Android:** reminders use exact-time OS alarms, which need a permission on
Android 12+. Two parts to this — both are required, the manifest line alone
is not enough:

1. Open `android/app/src/main/AndroidManifest.xml` and add this line inside
   the `<manifest>` tag (alongside any other `<uses-permission>` lines,
   above `<application>`):
   ```xml
   <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
   ```
2. The app now also requests the permission at startup (a system dialog or
   settings screen should pop up the first time you run it after this
   update). If you don't see that prompt, or already dismissed it once,
   grant it manually: **phone Settings → Apps → To-Do → Alarms & reminders
   → Allow**.

Without step 2 specifically, Android silently drops exact-time scheduling —
this is why reminders can work fine while the app is open (that's the
in-app popup, unrelated to this permission) but never arrive once you've
closed the app. If reminders still don't show up after granting it, also
check **Settings → Apps → To-Do → Battery** and make sure battery
optimization isn't set to aggressively restrict the app in the background.

Once granted, Android reminders are real OS alarms — they fire even if the
app is fully closed.

**Windows/macOS/Linux:** desktop reminders use `local_notifier`, since the
Android-focused notification plugin doesn't reliably support Windows. It
pops up a system notification while the app is running (a timer checks
every 20 seconds for anything due). Two things to know:
- The app needs to be running for a desktop reminder to fire — pin it to
  the corner with the mini-window button so it's always available, rather
  than closing it.
- Windows notifications sometimes don't display properly from a
  `flutter run` debug session because there's no Start Menu shortcut with a
  matching app ID yet — they're more reliable from a `flutter build windows`
  release build you've actually run once via its `.exe`. If you don't see a
  system popup during `flutter run`, don't worry — you'll also get a dialog
  inside the app either way (see below), which works regardless of
  OS-level notification support.

**In-app popup (all platforms):** whenever a reminder fires, you'll also get
a "Reminder" dialog right inside the app if it's open — this works
identically on every platform and doesn't depend on OS notification
permissions at all.

---

## Sync between Android and desktop

The code side is already done — `SyncService.enabled = true`, `sync_service.dart` has the
real Firestore implementation, `main.dart` initializes Firebase and gates the
app behind a sign-in screen (`login_screen.dart`), and `pubspec.yaml` has the
Firebase packages uncommented. **What's left is entirely steps only you can
do** — creating your own Firebase project and pointing this code at it:

1. Create a project at https://console.firebase.google.com (free "Spark" plan is enough).
2. Install the FlutterFire CLI:
   ```bash
   dart pub global activate flutterfire_cli
   ```
3. From the `todo_app` folder, run:
   ```bash
   flutterfire configure
   ```
   Select your project and the platforms you want (Android, Windows, etc).
   This generates `lib/firebase_options.dart` — **the app won't compile
   until this file exists**, since `main.dart` imports it directly.
4. In the Firebase console: **Build → Firestore Database → Create database**
   (start in test mode for development).
5. In the Firebase console: **Build → Authentication → Sign-in method** →
   enable **Email/Password**. (Not Anonymous — that ties to a single device
   and can't be shared between your phone and desktop, which is the whole
   point here.)
6. `flutter pub get`, then run on desktop first — you'll land on a sign-in
   screen. Tap "Don't have an account? Create one," pick any email/password
   (it doesn't need to be a real inbox — Firebase just uses it as your
   account identifier).
7. Run on Android and **sign in with that same email/password**. Add a task
   on one device — it should appear on the other within moments.

### Firestore security rules

Before going beyond testing, lock down your database in the Firebase console (Firestore → Rules):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/tasks/{taskId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    match /users/{userId}/fcmTokens/{tokenId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

This ensures each account can only read/write its own tasks and device tokens.

### Going back to offline-only mode

If you ever want to disable sync and go back to purely local storage, set
`SyncService.enabled = false` in `sync_service.dart` — `main.dart` already
checks that flag and skips the sign-in gate/Firebase entirely when it's off.

---

## Push notifications (arrive even when the app is fully closed)

This is the "Hay Day-style" notification setup — a push sent from outside your phone, rather than the phone scheduling its own alarm. It needs the Firestore sync above to already be set up (skip ahead and do that first if you haven't). **No Blaze plan or credit card required** — Firebase Cloud Messaging itself is free and unlimited; the trick is triggering it on a schedule using a free GitHub Actions cron job instead of Firebase's own (paid) Cloud Functions.

### 1. Enable the Flutter side

1. In `pubspec.yaml`, uncomment `firebase_messaging`.
2. In `lib/services/push_service.dart`, delete the stub `PushService` class at the top and uncomment the "REAL IMPLEMENTATION" block below it.
3. That's it for wiring — `main.dart` already calls `PushService().init()` automatically once sign-in completes (see `_AuthGate`), no extra edit needed there.
4. `flutter pub get`, then rebuild for Android.

### 2. Get a Firebase service account key

In the Firebase console: **Project settings (gear icon) → Service accounts → Generate new private key**. This downloads a JSON file — keep it secret, it has full admin access to your Firestore. You'll paste its contents into a GitHub secret in a moment, not into the app itself.

### 3. Set up the GitHub Actions bot

The `reminder-bot/` folder already has everything needed:
- `send-reminders.js` — checks Firestore every run for due reminders and sends them via FCM
- `package.json` — its one dependency (`firebase-admin`)
- `.github/workflows/send-reminders.yml` — the cron schedule

To wire it up:
1. Create a new GitHub repository (private is fine) and push this project to it.
2. **Move the workflow file** from `reminder-bot/.github/workflows/send-reminders.yml` to `.github/workflows/send-reminders.yml` at your **repo root** — GitHub only picks up workflows from that exact top-level location, not from subfolders. The `reminder-bot/` folder itself (with `package.json` and `send-reminders.js`) stays where it is.
3. In your repo on GitHub: **Settings → Secrets and variables → Actions → New repository secret**. Name it `FIREBASE_SERVICE_ACCOUNT_JSON`, and paste in the *entire contents* of the service account JSON file from step 2.
4. Go to the **Actions** tab, find "Send Due Reminders," and click **Run workflow** to test it manually before waiting for the schedule.

Once that test run succeeds, it'll run automatically every 5 minutes from then on, entirely free, with no server for you to maintain.

### How it fits together

1. Your phone registers its FCM token to Firestore when the app opens (via `push_service.dart`).
2. You add a task with a due date and reminders — it syncs to Firestore like any other task.
3. Every 5 minutes, the GitHub Action checks Firestore for anything due, sends a push via FCM, and marks it as fired in Firestore.
4. That "fired" update syncs back down to your phone automatically — the app's "🔔 fired/total" display updates without you doing anything.
5. The notification itself is delivered by Google Play Services, the same system-level channel every major app uses — the app doesn't need to be running, scheduled, or exempted from any battery optimization for this one, since it's Play Services (not your app) waking up briefly to show it.

### Note on timing precision

GitHub's free cron scheduling isn't second-precise — expect reminders to land within a few minutes of their exact time, occasionally more if GitHub's shared runners are under heavy load. That's a real tradeoff for "free and no server to maintain." If you ever need tighter precision, the same `send-reminders.js` logic can run on an always-on server or Firebase Cloud Functions with Cloud Scheduler instead — but that reintroduces the Blaze/credit-card requirement this approach was built to avoid.

---



## Project structure

```
lib/
  models/
    task.dart                   Task/subtask data model, including the
                                 due-date + multi-reminder-offset system
  services/
    storage_service.dart        Local offline storage (Hive)
    notification_service.dart   Android OS alarms + desktop popups (local_notifier)
    sync_service.dart           Optional Firestore cloud sync (stub by default)
    push_service.dart           Optional FCM push registration (stub by default)
    task_provider.dart          CRUD, reminder polling/firing, glues everything together
    window_service.dart         Desktop window control (mini/pin-to-corner mode)
    window_mode_notifier.dart   Tracks mini vs. normal UI mode
  screens/
    home_screen.dart            Full task list screen
    login_screen.dart           Email/password sign-in (required for cross-device sync)
  widgets/
    task_tile.dart               Main task row + expandable subtasks
    add_edit_task_dialog.dart    Create/edit dialog: due date + multi-reminder picker
    mini_window.dart             Compact pinned-to-corner view
  main.dart                      App entry point, in-app reminder popup wiring
reminder-bot/
  send-reminders.js             GitHub Actions script: checks Firestore, sends FCM pushes
  package.json                  Its one dependency (firebase-admin)
  .github/workflows/
    send-reminders.yml          Cron schedule — MOVE to repo root before use, see
                                 "Push notifications" section above
```

## Known limitations / next things worth adding

- No data migration between major reminder-system changes made during
  development — if you're upgrading from a much older copy of this app and
  your saved tasks lose their reminders, that's expected; titles/notes/due
  dates are unaffected.
- Drag-to-reorder tasks (the `order` field on `Task` is already there for this)
- Swipe-to-delete / swipe-to-complete gestures
- A proper login/signup screen if you enable email/password sync
- Recurring reminders (daily/weekly) — extend `NotificationService`
- Windows notifications during `flutter run` debug sessions can be
  unreliable (see the Reminders section above) — the in-app popup dialog is
  the reliable fallback everywhere

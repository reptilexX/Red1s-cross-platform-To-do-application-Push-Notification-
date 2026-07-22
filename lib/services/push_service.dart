// OPTIONAL — push notifications that arrive even when the app is fully
// closed, the same way Hay Day / WhatsApp / Gmail notifications work.
//
// This file is inert by default (all no-ops) because it needs the
// firebase_messaging package, which is commented out of pubspec.yaml
// until you're ready for it. To enable:
//
//   1. Finish the "Turn on sync" Firebase setup in README.md first —
//      this builds on top of that (needs Firestore + a signed-in user).
//   2. Uncomment firebase_messaging in pubspec.yaml.
//   3. In the Firebase console: Build → Cloud Messaging — no extra
//      setup needed there, it's on by default.
//   4. Uncomment the "real" implementation block below and delete the
//      stub above it.
//   5. Set up the companion GitHub Actions bot in /reminder-bot — see
//      README.md's "Push notifications" section for the full walkthrough.
//   6. Call `await pushService.init();` in main.dart, right after
//      `await sync.signInAnonymously();` (or your email sign-in call).

class PushService {
  Future<void> init() async {
    // no-op until firebase_messaging is enabled — see instructions above
  }
}

/* ---------------------------------------------------------------------
REAL IMPLEMENTATION — uncomment this whole block (and delete the stub
class above) once firebase_messaging is added to pubspec.yaml.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Must be a top-level function (not a class method) — this is what
// Android calls in a fresh background isolate when a push arrives while
// the app isn't running. FCM shows the system notification automatically
// for messages with a "notification" payload (which is all the
// reminder-bot sends), so there's nothing else to do here — but the
// handler must exist and be registered for background delivery to work.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushService {
  final _messaging = FirebaseMessaging.instance;

  Future<void> init() async {
    await _messaging.requestPermission();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return; // not signed in yet — nothing to register

    final token = await _messaging.getToken();
    if (token != null) await _saveToken(uid, token);

    // Tokens can change (app reinstall, etc.) — keep Firestore current.
    _messaging.onTokenRefresh.listen((newToken) => _saveToken(uid, newToken));
  }

  Future<void> _saveToken(String uid, String token) async {
    // One doc per device/token, so a user can have the app open on
    // several devices and get the push on all of them.
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(token)
        .set({'updatedAt': DateTime.now().toIso8601String()});
  }
}
--------------------------------------------------------------------- */

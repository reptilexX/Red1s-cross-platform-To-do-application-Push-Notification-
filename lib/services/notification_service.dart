import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

/// Schedules and shows reminder notifications.
///
/// - **Android**: uses flutter_local_notifications to schedule a real
///   OS-level alarm at the exact reminder time. This fires even if the
///   app is closed or the phone is idle (subject to Android battery
///   optimizations).
/// - **Windows / macOS / Linux**: flutter_local_notifications does not
///   reliably support Windows, so desktop uses local_notifier instead.
///   local_notifier can only show a notification *immediately* — it has
///   no built-in scheduler — so [TaskProvider] polls for due reminders
///   with a periodic timer while the app is running and calls
///   [showNow] at the right moment. This means: on desktop, the app
///   needs to be running (it can be minimized/pinned to a corner) for
///   the reminder to pop up.
class NotificationService {
  final FlutterLocalNotificationsPlugin _androidPlugin =
      FlutterLocalNotificationsPlugin();

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> init() async {
    if (_isAndroid) {
      tz_data.initializeTimeZones();

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _androidPlugin.initialize(initSettings);

      final androidImpl = _androidPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // Android 13+ requires runtime notification permission.
      await androidImpl?.requestNotificationsPermission();

      // Android 12+ separately requires "exact alarm" permission for
      // precise-time reminders. Declaring it in AndroidManifest.xml is
      // NOT enough by itself — the OS still needs explicit user
      // approval, either via this prompt (which opens the system
      // settings screen) or manually through
      // Settings > Apps > To-Do > Alarms & reminders. Without this,
      // scheduled reminders silently never fire once the app is closed.
      await androidImpl?.requestExactAlarmsPermission();
    } else if (_isDesktop) {
      await localNotifier.setup(
        appName: 'To-Do',
        // Windows requires a shortcut with a matching AppUserModelID for
        // notifications to display reliably outside of debug builds.
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    }
  }

  /// Android only: schedules a real OS alarm for [scheduledTime].
  /// [id] should be a stable integer derived from the task id.
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (!_isAndroid) return;
    if (scheduledTime.isBefore(DateTime.now())) return;

    await _androidPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          'Task Reminders',
          channelDescription: 'Reminders for your to-do tasks',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelReminder(int id) async {
    if (!_isAndroid) return;
    await _androidPlugin.cancel(id);
  }

  /// Desktop only: pops up a system notification immediately. Called by
  /// TaskProvider's reminder-polling timer when a reminder comes due.
  Future<void> showNow({required String title, required String body}) async {
    if (!_isDesktop) return;
    final notification = LocalNotification(title: title, body: body);
    await notification.show();
  }
}

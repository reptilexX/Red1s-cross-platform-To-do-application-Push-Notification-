import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'services/task_provider.dart';
import 'services/window_service.dart';
import 'services/window_mode_notifier.dart';
import 'services/push_service.dart';
import 'models/task.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/mini_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Sets up the desktop window (size, centering). No-op on Android/iOS/web.
  await WindowService.init();

  final storage = StorageService();
  await storage.init();

  final notifications = NotificationService();
  await notifications.init();

  final sync = SyncService();

  final taskProvider = TaskProvider(
    storage: storage,
    notifications: notifications,
    sync: sync,
  );

  // Sync needs a signed-in user before it means anything — task
  // loading is deferred until sign-in completes (see _AuthGate below).
  // If you ever set SyncService.enabled = false to go back to purely
  // local/offline mode, load immediately instead:
  if (!SyncService.enabled) {
    await taskProvider.loadTasks();
  }

  runApp(MyApp(taskProvider: taskProvider, sync: sync));
}

class MyApp extends StatefulWidget {
  final TaskProvider taskProvider;
  final SyncService sync;
  const MyApp({super.key, required this.taskProvider, required this.sync});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<ReminderEvent>? _reminderSub;

  @override
  void initState() {
    super.initState();
    // Show an in-app popup whenever a reminder comes due, no matter
    // which screen (normal or mini) is currently showing.
    _reminderSub = widget.taskProvider.dueReminders.listen(_showReminderDialog);
  }

  void _showReminderDialog(ReminderEvent event) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final task = event.task;
    final isMini = context.read<WindowModeNotifier>().isMini;

    // Which reminder this actually is (e.g. "1 hour before"), not just
    // the task's title repeated — and if it's a subtask, whose task it
    // belongs to, since subtasks otherwise look like unrelated tasks.
    final offsetLabel = event.offsetsMinutes.length == 1
        ? reminderOffsetLabel(event.offsetsMinutes.first)
        : '${event.offsetsMinutes.length} reminders due';
    final parent =
        task.parentTaskId != null ? widget.taskProvider.taskById(task.parentTaskId!) : null;
    final subLabel = parent != null ? '$offsetLabel · Subtask of "${parent.title}"' : offsetLabel;

    showDialog(
      context: context,
      builder: (ctx) => isMini
          ? _MiniReminderDialog(task: task, subLabel: subLabel)
          : AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.alarm, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Reminder'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subLabel, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (task.notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(task.notes),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.taskProvider),
        ChangeNotifierProvider(create: (_) => WindowModeNotifier()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'To-Do',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: SyncService.enabled
            ? _AuthGate(taskProvider: widget.taskProvider, sync: widget.sync)
            : const _ModeSwitcher(key: ValueKey('offline')),
      ),
    );
  }
}

/// Shown only when SyncService.enabled. Blocks access behind sign-in
/// (needed since two devices must share the same account to sync), and
/// loads tasks exactly once, right after the user is confirmed signed in.
class _AuthGate extends StatefulWidget {
  final TaskProvider taskProvider;
  final SyncService sync;
  const _AuthGate({required this.taskProvider, required this.sync});

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _tasksLoaded = false;
  bool _pushInitialized = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: widget.sync.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(sync: widget.sync);
        }

        if (!_tasksLoaded) {
          _tasksLoaded = true;
          widget.taskProvider.loadTasks();
        }
        if (!_pushInitialized) {
          _pushInitialized = true;
          // No-op until push notifications are enabled — see
          // README.md's "Push notifications" section.
          PushService().init();
        }

        return const _ModeSwitcher(key: ValueKey('online'));
      },
    );
  }
}

/// Switches between the normal full window and the compact pinned
/// "mini" window on desktop. Keyed so Flutter fully discards the old
/// screen's state instead of trying to reuse it on switch.
class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WindowModeNotifier>(
      builder: (context, windowMode, _) {
        return windowMode.isMini
            ? const MiniWindow(key: ValueKey('mini'))
            : const HomeScreen(key: ValueKey('normal'));
      },
    );
  }
}
class _MiniReminderDialog extends StatelessWidget {
  final Task task;
  final String subLabel;

  const _MiniReminderDialog({
    super.key,
    required this.task,
    required this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.alarm, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Text('Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(subLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (task.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.notes),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Dismiss'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
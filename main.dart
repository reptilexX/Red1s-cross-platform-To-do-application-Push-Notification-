import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'services/task_provider.dart';
import 'services/window_service.dart';
import 'services/window_mode_notifier.dart';
import 'models/task.dart';
import 'screens/home_screen.dart';
import 'widgets/mini_window.dart';

// To enable cross-device cloud sync, uncomment the two lines below and
// the Firebase.initializeApp() call, after following README.md to set
// up your Firebase project with `flutterfire configure`.
// import 'package:firebase_core/firebase_core.dart';
// import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // SyncService.enabled = true; // flip on once Firebase is configured

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
  await taskProvider.loadTasks();

  runApp(MyApp(taskProvider: taskProvider));
}

class MyApp extends StatefulWidget {
  final TaskProvider taskProvider;
  const MyApp({super.key, required this.taskProvider});

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
      builder: (ctx) => AlertDialog(
        insetPadding: isMini
            ? const EdgeInsets.all(8)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        titlePadding: isMini
            ? const EdgeInsets.fromLTRB(12, 12, 12, 0)
            : const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: isMini
            ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
            : const EdgeInsets.fromLTRB(24, 20, 24, 24),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm, color: Colors.orange, size: isMini ? 18 : 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Reminder',
                style: isMini ? const TextStyle(fontSize: 15) : null,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isMini ? 13 : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subLabel,
              style: TextStyle(
                fontSize: isMini ? 11 : 13,
                color: Colors.grey,
              ),
            ),
            if (task.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.notes, style: TextStyle(fontSize: isMini ? 12 : null)),
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
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: Consumer<WindowModeNotifier>(
          builder: (context, windowMode, _) {
            // Keyed so Flutter fully discards the old screen's state
            // instead of trying to reuse it — guarantees a clean switch.
            return windowMode.isMini
                ? const MiniWindow(key: ValueKey('mini'))
                : const HomeScreen(key: ValueKey('normal'));
          },
        ),
      ),
    );
  }
}

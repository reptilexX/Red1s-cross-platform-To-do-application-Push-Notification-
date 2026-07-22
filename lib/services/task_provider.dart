import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'sync_service.dart';

/// A reminder that just came due: the (updated) task it belongs to,
/// plus which offset(s) fired it — so the UI can say *which* reminder
/// this is, not just repeat the task's title/notes.
class ReminderEvent {
  final Task task;
  final List<int> offsetsMinutes;
  ReminderEvent(this.task, this.offsetsMinutes);
}

/// Central place the UI talks to. Handles CRUD, keeps local storage,
/// notifications, and (optionally) cloud sync all in agreement. Also
/// polls for due reminders so desktop (which has no OS-level scheduler)
/// can pop up notifications while the app is running.
class TaskProvider extends ChangeNotifier {
  final StorageService storage;
  final NotificationService notifications;
  final SyncService sync;
  final _uuid = const Uuid();

  List<Task> _tasks = [];
  Timer? _reminderTimer;

  /// Fires whenever a reminder comes due, so the UI (any screen) can
  /// show an in-app popup regardless of platform.
  final _dueRemindersController = StreamController<ReminderEvent>.broadcast();
  Stream<ReminderEvent> get dueReminders => _dueRemindersController.stream;

  TaskProvider({
    required this.storage,
    required this.notifications,
    required this.sync,
  });

  Future<void> loadTasks() async {
    _tasks = storage.getAllTasks();
    notifyListeners();

    if (SyncService.enabled) {
      sync.taskStream().listen((remoteTasks) async {
        for (final t in remoteTasks) {
          await storage.saveTask(t);
        }
        _tasks = storage.getAllTasks();
        notifyListeners();
      });
    }

    _startReminderPolling();
  }

  /// Checks every 20 seconds for any reminder offset whose time has
  /// passed. Android also gets a real OS alarm per offset (see
  /// _persist), so this mainly matters for desktop, but it also drives
  /// the in-app popup dialog everywhere.
  void _startReminderPolling() {
    _reminderTimer?.cancel();
    _reminderTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkDueReminders();
      // _checkDueReminders() only calls notifyListeners() when a reminder
      // actually fires. Without this, a task with no reminders (or whose
      // reminders have all already fired) never rebuilds as time passes,
      // so its "Overdue" badge goes stale until something else happens
      // to touch the list.
      notifyListeners();
    });
    _checkDueReminders();
  }

  void _checkDueReminders() {
    final now = DateTime.now();
    for (final task in _tasks) {
      if (task.dueDate == null || task.isComplete) continue;

      final due = <int>[];
      for (final offset in task.reminderOffsetsMinutes) {
        if (task.firedOffsetsMinutes.contains(offset)) continue;
        final target = task.dueDate!.subtract(Duration(minutes: offset));
        if (!target.isAfter(now)) due.add(offset);
      }
      if (due.isNotEmpty) _fireReminders(task, due);
    }
  }

  Future<void> _fireReminders(Task task, List<int> offsetsNowDue) async {
    final updated = task.copyWith(
      firedOffsetsMinutes: [...task.firedOffsetsMinutes, ...offsetsNowDue],
    );
    await storage.saveTask(updated);
    final idx = _tasks.indexWhere((t) => t.id == task.id);
    if (idx != -1) _tasks[idx] = updated;

    // Without this, the remote copy never learns this offset fired.
    // Firestore's snapshots() listener re-sends the WHOLE collection on
    // every change (not just a diff) — so the next time *any* task
    // changes, this task's stale "not fired yet" remote copy comes back
    // down and overwrites the local "fired" record, making the reminder
    // look unsent again and fire a second time.
    if (SyncService.enabled) {
      await sync.pushTask(updated);
    }

    if (!(!kIsWeb && Platform.isAndroid)) {
      // Android already got a real OS alarm per offset from
      // scheduleReminder; desktop needs us to pop it up now.
      final label = offsetsNowDue.length == 1
          ? reminderOffsetLabel(offsetsNowDue.first)
          : '${offsetsNowDue.length} reminders due';
      await notifications.showNow(
        title: task.title,
        body: task.notes.isNotEmpty ? '$label — ${task.notes}' : label,
      );
    }

    _dueRemindersController.add(ReminderEvent(updated, offsetsNowDue));
    notifyListeners();
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _dueRemindersController.close();
    super.dispose();
  }

  List<Task> get mainTasks =>
      _tasks.where((t) => t.parentTaskId == null).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  List<Task> subtasksOf(String parentId) =>
      _tasks.where((t) => t.parentTaskId == parentId).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  Task? taskById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<Task> addTask({
    required String title,
    String notes = '',
    DateTime? dueDate,
    List<int> reminderOffsetsMinutes = const [],
    String? parentTaskId,
  }) async {
    final task = Task(
      id: _uuid.v4(),
      title: title,
      notes: notes,
      dueDate: dueDate,
      reminderOffsetsMinutes: reminderOffsetsMinutes,
      parentTaskId: parentTaskId,
    );
    await _persist(task, previous: null);
    return task;
  }

  Future<void> updateTask(Task updated) async {
    final previous = _tasks.firstWhere(
      (t) => t.id == updated.id,
      orElse: () => updated,
    );
    await _persist(updated, previous: previous);
  }

  Future<void> toggleComplete(Task task) async {
    await updateTask(task.copyWith(isComplete: !task.isComplete));
  }

  Future<void> deleteTask(Task task) async {
    await storage.deleteTaskWithSubtasks(task.id);
    for (final offset in task.reminderOffsetsMinutes) {
      await notifications.cancelReminder(_alarmId(task.id, offset));
    }
    if (SyncService.enabled) {
      await sync.deleteTaskRemote(task.id);
    }
    _tasks = storage.getAllTasks();
    notifyListeners();
  }

  /// Stable per-(task, offset) id for Android's OS alarm scheduler.
  int _alarmId(String taskId, int offsetMinutes) =>
      '${taskId}_$offsetMinutes'.hashCode;

  Future<void> _persist(Task task, {required Task? previous}) async {
    await storage.saveTask(task);

    // Cancel Android alarms for any offset that existed before but
    // isn't in the new set (e.g. removed, or due date changed).
    if (previous != null) {
      for (final offset in previous.reminderOffsetsMinutes) {
        if (!task.reminderOffsetsMinutes.contains(offset)) {
          await notifications.cancelReminder(_alarmId(task.id, offset));
        }
      }
    }

    // Schedule Android alarms for every current, not-yet-fired offset.
    if (task.dueDate != null && !task.isComplete) {
      for (final offset in task.reminderOffsetsMinutes) {
        final alarmId = _alarmId(task.id, offset);
        await notifications.cancelReminder(alarmId);
        if (!task.firedOffsetsMinutes.contains(offset)) {
          final target = task.dueDate!.subtract(Duration(minutes: offset));
          await notifications.scheduleReminder(
            id: alarmId,
            title: task.title,
            body: task.notes.isNotEmpty
                ? '${reminderOffsetLabel(offset)} — ${task.notes}'
                : reminderOffsetLabel(offset),
            scheduledTime: target,
          );
        }
      }
    } else {
      for (final offset in task.reminderOffsetsMinutes) {
        await notifications.cancelReminder(_alarmId(task.id, offset));
      }
    }

    _tasks = storage.getAllTasks();

    if (SyncService.enabled) {
      await sync.pushTask(task);
    }

    notifyListeners();
  }
}
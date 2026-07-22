import 'package:hive_flutter/hive_flutter.dart';
import '../models/task.dart';

/// Handles reading/writing tasks to the local on-device database (Hive).
/// This works fully offline. When cloud sync is enabled, [SyncService]
/// mirrors changes here to Firestore and vice versa.
class StorageService {
  static const String _boxName = 'tasks';
  late Box<Map> _box;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<Map>(_boxName);
  }

  List<Task> getAllTasks() {
    return _box.values.map((m) => Task.fromMap(m)).toList();
  }

  Future<void> saveTask(Task task) async {
    await _box.put(task.id, task.toMap());
  }

  Future<void> deleteTask(String id) async {
    await _box.delete(id);
  }

  /// Deletes a task and all of its subtasks.
  Future<void> deleteTaskWithSubtasks(String id) async {
    final subtaskIds = _box.values
        .map((m) => Task.fromMap(m))
        .where((t) => t.parentTaskId == id)
        .map((t) => t.id)
        .toList();
    await _box.delete(id);
    for (final subId in subtaskIds) {
      await _box.delete(subId);
    }
  }

  Task? getTask(String id) {
    final m = _box.get(id);
    return m != null ? Task.fromMap(m) : null;
  }

  /// Listen for any change to the box (used to refresh the UI).
  Stream<BoxEvent> watch() => _box.watch();
}

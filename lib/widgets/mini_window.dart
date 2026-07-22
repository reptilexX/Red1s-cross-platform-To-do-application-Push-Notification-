import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/task_provider.dart';
import '../services/window_mode_notifier.dart';

/// Bare-bones compact view shown when pinned to a corner: just
/// checkboxes and titles, nothing else. Full editing, notes, due dates,
/// and adding tasks happen in the normal window. Dragging, minimizing,
/// and closing are handled by the normal OS title bar above this.
class MiniWindow extends StatelessWidget {
  const MiniWindow({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final tasks = provider.mainTasks;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 32,
        title: const Text('To-Do', style: TextStyle(fontSize: 13)),
        actions: [
          IconButton(
            tooltip: 'Restore full window',
            iconSize: 16,
            icon: const Icon(Icons.open_in_full),
            onPressed: () => context.read<WindowModeNotifier>().exitMiniMode(),
          ),
        ],
      ),
      body: tasks.isEmpty
          ? const Center(
              child: Text('No tasks', style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          : ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  value: task.isComplete,
                  onChanged: (_) =>
                      context.read<TaskProvider>().toggleComplete(task),
                  title: Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 12,
                      decoration:
                          task.isComplete ? TextDecoration.lineThrough : null,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

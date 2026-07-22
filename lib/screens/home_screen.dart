import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/task_provider.dart';
import '../services/window_service.dart';
import '../services/window_mode_notifier.dart';
import '../widgets/task_tile.dart';
import '../widgets/add_edit_task_dialog.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final mainTasks = provider.mainTasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        actions: [
          if (WindowService.isDesktop)
            IconButton(
              tooltip: 'Pin mini window to corner',
              icon: const Icon(Icons.picture_in_picture_alt),
              onPressed: () =>
                  context.read<WindowModeNotifier>().enterMiniMode(),
            ),
        ],
      ),
      body: mainTasks.isEmpty
          ? const Center(
              child: Text(
                'No tasks yet.\nTap + to add your first task.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              itemCount: mainTasks.length,
              itemBuilder: (context, index) =>
                  TaskTile(task: mainTasks[index]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const AddEditTaskDialog(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
    );
  }
}

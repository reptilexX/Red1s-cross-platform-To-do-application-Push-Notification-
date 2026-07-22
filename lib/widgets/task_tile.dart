import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../services/task_provider.dart';
import 'add_edit_task_dialog.dart';

/// Renders a main task with an expandable list of its subtasks.
///
/// Uses a manually-built header row (rather than ExpansionTile's
/// built-in one) so the checkbox, title/subtitle, menu button, and
/// expand arrow are always vertically centered against each other
/// consistently — ExpansionTile centers its arrow against the *whole*
/// tile (title+subtitle) while inline widgets in the title only center
/// against the title line, so they'd drift out of alignment whenever a
/// subtitle was present.
class TaskTile extends StatefulWidget {
  final Task task;
  const TaskTile({super.key, required this.task});

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final task = widget.task;
    final subtasks = provider.subtasksOf(task.id);
    final doneCount = subtasks.where((s) => s.isComplete).length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: task.isComplete,
                    onChanged: (_) =>
                        context.read<TaskProvider>().toggleComplete(task),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            decoration:
                                task.isComplete ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: taskInfoRow(
                            task,
                            subtaskSummary: subtasks.isNotEmpty
                                ? '$doneCount/${subtasks.length} subtasks'
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        showDialog(
                          context: context,
                          builder: (_) => AddEditTaskDialog(existingTask: task),
                        );
                      } else if (value == 'delete') {
                        context.read<TaskProvider>().deleteTask(task);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(subtasks.isNotEmpty
                            ? 'Delete (and ${subtasks.length} subtask${subtasks.length == 1 ? '' : 's'})'
                            : 'Delete'),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            if (task.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    task.notes,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                ),
              ),
            ...subtasks.map((s) => _SubtaskRow(task: s)),
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add subtask'),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AddEditTaskDialog(parentTaskId: task.id),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  final Task task;
  const _SubtaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: task.isComplete,
            onChanged: (_) => context.read<TaskProvider>().toggleComplete(task),
          ),
          Expanded(
            child: InkWell(
              onTap: () => showDialog(
                context: context,
                builder: (_) => AddEditTaskDialog(existingTask: task),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 14,
                        decoration:
                            task.isComplete ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (task.notes.isNotEmpty)
                      Text(
                        task.notes,
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: taskInfoRow(task),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                showDialog(
                  context: context,
                  builder: (_) => AddEditTaskDialog(existingTask: task),
                );
              } else if (value == 'delete') {
                context.read<TaskProvider>().deleteTask(task);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared due-date/reminder/subtask info row, used by both main task
/// tiles and subtask rows so their status indicators stay consistent.
///
/// - Due date turns red/bold and says "Overdue" once it's passed and
///   the task isn't complete yet.
/// - Reminder count shows how many have actually fired vs. the total
///   ("2/3 sent") so it's obvious whether anything is still pending —
///   grey once everything's fired, amber while some are still ahead.
Widget taskInfoRow(Task task, {String? subtaskSummary}) {
  final now = DateTime.now();
  final isOverdue =
      task.dueDate != null && task.dueDate!.isBefore(now) && !task.isComplete;

  final chunks = <Widget>[];

  if (task.dueDate != null) {
    String dueText;
    if (isOverdue) {
      final overdueDuration = now.difference(task.dueDate!);
      final String byLabel;
      if (overdueDuration.inDays >= 1) {
        byLabel = '${overdueDuration.inDays}d';
      } else if (overdueDuration.inHours >= 1) {
        byLabel = '${overdueDuration.inHours}h';
      } else {
        byLabel = '${overdueDuration.inMinutes}m';
      }
      dueText =
          '⚠ Overdue by $byLabel — ${DateFormat('MMM d, h:mm a').format(task.dueDate!)}';
    } else {
      dueText = '📅 ${DateFormat('MMM d, h:mm a').format(task.dueDate!)}';
    }
    chunks.add(Text(
      dueText,
      style: TextStyle(
        fontSize: 12,
        color: isOverdue ? Colors.redAccent.shade100 : null,
        fontWeight: isOverdue ? FontWeight.bold : null,
      ),
    ));
  }

  if (task.reminderOffsetsMinutes.isNotEmpty) {
    final total = task.reminderOffsetsMinutes.length;
    final fired = task.firedOffsetsMinutes.length;
    final allFired = fired >= total;
    chunks.add(Text(
      '🔔 $fired/$total sent',
      style: TextStyle(
        fontSize: 12,
        color: allFired ? Colors.grey.shade500 : Colors.amber.shade300,
      ),
    ));
  }

  if (subtaskSummary != null) {
    chunks.add(Text(subtaskSummary, style: const TextStyle(fontSize: 12)));
  }

  if (chunks.isEmpty) return const SizedBox.shrink();
  return Wrap(spacing: 10, runSpacing: 2, children: chunks);
}

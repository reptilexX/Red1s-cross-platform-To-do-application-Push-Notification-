import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../services/task_provider.dart';

/// Dialog used both for creating a new task/subtask and editing an
/// existing one. Supports multiple reminders per task (e.g. 1 day
/// before AND 1 hour before AND at the due time), all anchored to a
/// single due date so they move together if you edit it.
class AddEditTaskDialog extends StatefulWidget {
  final Task? existingTask;
  final String? parentTaskId; // set when adding a subtask

  const AddEditTaskDialog({super.key, this.existingTask, this.parentTaskId});

  @override
  State<AddEditTaskDialog> createState() => _AddEditTaskDialogState();
}

class _AddEditTaskDialogState extends State<AddEditTaskDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  DateTime? _dueDate;
  late Set<int> _selectedOffsets; // minutes before due date

  static const List<int> _presetOffsets = [0, 10, 60, 120, 1440];

  @override
  void initState() {
    super.initState();
    final t = widget.existingTask;
    _titleController = TextEditingController(text: t?.title ?? '');
    _notesController = TextEditingController(text: t?.notes ?? '');
    _dueDate = t?.dueDate;
    _selectedOffsets = {...(t?.reminderOffsetsMinutes ?? [])};
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _dueDate != null
          ? TimeOfDay.fromDateTime(_dueDate!)
          : TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))),
    );
    if (time == null) return;

    setState(() {
      _dueDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _addCustomOffset() async {
    int days = 0, hours = 0, minutes = 0;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Remind me before due, by...'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _numberField('Days', (v) => setDialogState(() => days = v)),
              const SizedBox(width: 8),
              _numberField('Hours', (v) => setDialogState(() => hours = v)),
              const SizedBox(width: 8),
              _numberField('Min', (v) => setDialogState(() => minutes = v)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final total = days * 1440 + hours * 60 + minutes;
                Navigator.of(context).pop(total);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result > 0) {
      setState(() => _selectedOffsets.add(result));
    }
  }

  Widget _numberField(String label, void Function(int) onChanged) {
    return SizedBox(
      width: 70,
      child: TextField(
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.number,
        onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
      ),
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final provider = context.read<TaskProvider>();
    final offsets = _dueDate == null ? <int>[] : _selectedOffsets.toList();

    if (widget.existingTask != null) {
      provider.updateTask(widget.existingTask!.copyWith(
        title: title,
        notes: _notesController.text.trim(),
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
        reminderOffsetsMinutes: offsets,
      ));
    } else {
      provider.addTask(
        title: title,
        notes: _notesController.text.trim(),
        dueDate: _dueDate,
        reminderOffsetsMinutes: offsets,
        parentTaskId: widget.parentTaskId,
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isSubtask = widget.parentTaskId != null;
    final customOffsets =
        _selectedOffsets.where((o) => !_presetOffsets.contains(o)).toList()
          ..sort();

    return AlertDialog(
      title: Text(widget.existingTask != null
          ? 'Edit task'
          : (isSubtask ? 'New subtask' : 'New task')),
      content: SingleChildScrollView(
        // Dismisses the keyboard (and its text-selection drag handle)
        // as soon as the user starts scrolling. Without this, the
        // handle can visually detach and "float" in place instead of
        // scrolling with the Notes field — a known Flutter quirk with
        // text fields inside a scrollable.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_dueDate == null
                  ? 'Set due date'
                  : DateFormat('MMM d, y, h:mm a').format(_dueDate!)),
              subtitle: const Text('When this task is due'),
              trailing: _dueDate != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _dueDate = null;
                        _selectedOffsets.clear();
                      }),
                    )
                  : null,
              onTap: _pickDueDate,
            ),

            if (_dueDate != null) ...[
              const SizedBox(height: 12),
              Text('Remind me (pick as many as you like)',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._presetOffsets.map(_offsetChip),
                  ...customOffsets.map(_offsetChip),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Custom', style: TextStyle(fontSize: 12)),
                    onPressed: _addCustomOffset,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_selectedOffsets.isNotEmpty)
                _buildSummary()
              else
                Text('No reminders selected',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _offsetChip(int minutes) {
    final selected = _selectedOffsets.contains(minutes);
    return FilterChip(
      label: Text(reminderOffsetLabel(minutes), style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (v) => setState(() {
        if (v) {
          _selectedOffsets.add(minutes);
        } else {
          _selectedOffsets.remove(minutes);
        }
      }),
    );
  }

  Widget _buildSummary() {
    final times = _selectedOffsets.map((m) => _dueDate!.subtract(Duration(minutes: m))).toList()
      ..sort();
    final now = DateTime.now();
    final anyPast = times.any((t) => t.isBefore(now));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...times.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  const Icon(Icons.alarm, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('MMM d, h:mm a').format(t),
                    style: TextStyle(
                      fontSize: 12,
                      color: t.isBefore(now) ? Colors.orange.shade300 : null,
                    ),
                  ),
                ],
              ),
            )),
        if (anyPast)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '⚠ Reminders in the past will fire immediately once saved.',
              style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

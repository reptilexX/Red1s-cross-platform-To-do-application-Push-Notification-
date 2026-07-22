/// A single task or subtask.
///
/// Main tasks have [parentTaskId] == null.
/// Subtasks have [parentTaskId] set to the id of their main task.
///
/// Reminders are expressed as offsets (in minutes) *before* [dueDate] —
/// e.g. 0 = "at the due time", 60 = "1 hour before". A task can have
/// several at once (e.g. 1 day before AND 1 hour before AND at the due
/// time). Because they're stored as offsets rather than fixed times,
/// editing the due date automatically moves every reminder with it.
class Task {
  final String id;
  String title;
  String notes;
  bool isComplete;
  DateTime? dueDate;
  List<int> reminderOffsetsMinutes; // minutes before dueDate; 0 = at due time
  List<int> firedOffsetsMinutes; // which of the above have already notified
  String? parentTaskId;
  int order;
  final DateTime createdAt;
  DateTime updatedAt;

  Task({
    required this.id,
    required this.title,
    this.notes = '',
    this.isComplete = false,
    this.dueDate,
    List<int>? reminderOffsetsMinutes,
    List<int>? firedOffsetsMinutes,
    this.parentTaskId,
    this.order = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : reminderOffsetsMinutes = reminderOffsetsMinutes ?? [],
        firedOffsetsMinutes = firedOffsetsMinutes ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isSubtask => parentTaskId != null;
  bool get hasReminders => dueDate != null && reminderOffsetsMinutes.isNotEmpty;

  /// All reminder moments as actual DateTimes, soonest first.
  List<DateTime> get reminderTimes {
    if (dueDate == null) return [];
    return reminderOffsetsMinutes
        .map((m) => dueDate!.subtract(Duration(minutes: m)))
        .toList()
      ..sort();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'notes': notes,
      'isComplete': isComplete,
      'dueDate': dueDate?.toIso8601String(),
      'reminderOffsetsMinutes': reminderOffsetsMinutes,
      'firedOffsetsMinutes': firedOffsetsMinutes,
      'parentTaskId': parentTaskId,
      'order': order,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Task.fromMap(Map<dynamic, dynamic> map) {
    return Task(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      isComplete: map['isComplete'] as bool? ?? false,
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
      reminderOffsetsMinutes: (map['reminderOffsetsMinutes'] as List?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      firedOffsetsMinutes:
          (map['firedOffsetsMinutes'] as List?)?.map((e) => e as int).toList() ??
              [],
      parentTaskId: map['parentTaskId'] as String?,
      order: map['order'] as int? ?? 0,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
    );
  }

  Task copyWith({
    String? title,
    String? notes,
    bool? isComplete,
    DateTime? dueDate,
    bool clearDueDate = false,
    List<int>? reminderOffsetsMinutes,
    List<int>? firedOffsetsMinutes,
    String? parentTaskId,
    int? order,
  }) {
    final dueDateChanged = clearDueDate ||
        (dueDate != null && dueDate != this.dueDate);
    final offsetsChanged = reminderOffsetsMinutes != null &&
        !_sameInts(reminderOffsetsMinutes, this.reminderOffsetsMinutes);

    return Task(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      isComplete: isComplete ?? this.isComplete,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reminderOffsetsMinutes: clearDueDate
          ? []
          : (reminderOffsetsMinutes ?? this.reminderOffsetsMinutes),
      // Reset "already fired" whenever the due date or the set of
      // offsets changes, so reminders can fire again on their new times.
      firedOffsetsMinutes: (dueDateChanged || offsetsChanged || clearDueDate)
          ? []
          : (firedOffsetsMinutes ?? this.firedOffsetsMinutes),
      parentTaskId: parentTaskId ?? this.parentTaskId,
      order: order ?? this.order,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  static bool _sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final sa = [...a]..sort();
    final sb = [...b]..sort();
    for (var i = 0; i < sa.length; i++) {
      if (sa[i] != sb[i]) return false;
    }
    return true;
  }
}

/// Turns a "minutes before due" offset into a human label.
String reminderOffsetLabel(int minutes) {
  if (minutes == 0) return 'At due time';
  if (minutes < 60) return '$minutes min before';
  if (minutes < 1440) {
    final h = minutes / 60;
    return '${h == h.roundToDouble() ? h.toInt() : h.toStringAsFixed(1)} hour${h == 1 ? '' : 's'} before';
  }
  final d = minutes / 1440;
  return '${d == d.roundToDouble() ? d.toInt() : d.toStringAsFixed(1)} day${d == 1 ? '' : 's'} before';
}

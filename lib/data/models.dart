import '../core/dates.dart';
import '../l10n/l10n.dart';

enum TaskStatus {
  todo('todo', 'To Do'),
  inProgress('in_progress', 'In Progress'),
  done('done', 'Completed');

  const TaskStatus(this.key, this.en);
  final String key;

  /// English label; [label] is the translated one.
  final String en;
  String get label => tr(en);

  static TaskStatus parse(String? key) =>
      values.firstWhere((s) => s.key == key, orElse: () => TaskStatus.todo);
}

enum Priority {
  urgent('urgent', 'Urgent', 0),
  normal('normal', 'Normal', 1),
  low('low', 'Low', 2);

  const Priority(this.key, this.en, this.rank);
  final String key;

  /// English label; [label] is the translated one.
  final String en;
  String get label => tr(en);

  /// Lower sorts first.
  final int rank;

  static Priority parse(String? key) =>
      values.firstWhere((p) => p.key == key, orElse: () => Priority.normal);
}

enum Recurrence {
  none('none', 'Never'),
  daily('daily', 'Every day'),
  weekly('weekly', 'Every week'),
  monthly('monthly', 'Every month');

  const Recurrence(this.key, this.en);
  final String key;

  /// English label; [label] is the translated one.
  final String en;
  String get label => tr(en);

  static Recurrence parse(String? key) =>
      values.firstWhere((r) => r.key == key, orElse: () => Recurrence.none);

  DateTime next(DateTime from) => switch (this) {
    Recurrence.daily => addDays(from, 1),
    Recurrence.weekly => addDays(from, 7),
    Recurrence.monthly => addMonths(from, 1),
    Recurrence.none => from,
  };
}

/// Every syncable record carries `updatedAt` and a `deletedAt` tombstone so a
/// future cloud sync can merge by last-writer-wins without losing deletions.
abstract class Record {
  String get id;
  DateTime get updatedAt;
  DateTime? get deletedAt;
  bool get isDeleted => deletedAt != null;
}

class Company extends Record {
  Company({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    required this.sortOrder,
    this.isPersonal = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  final String id;
  String name;
  int color;
  String icon;
  double sortOrder;
  bool isPersonal;
  DateTime createdAt;
  @override
  DateTime updatedAt;
  @override
  DateTime? deletedAt;

  /// First letter for avatars, works for Arabic names too.
  String get initial {
    final t = name.trim();
    return t.isEmpty ? '?' : String.fromCharCode(t.runes.first).toUpperCase();
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'color': color,
    'icon': icon,
    'sort_order': sortOrder,
    'is_personal': isPersonal ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
  };

  factory Company.fromMap(Map<String, Object?> m) => Company(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    color: (m['color'] as num?)?.toInt() ?? 0xFF4C6EF5,
    icon: m['icon'] as String? ?? 'work',
    sortOrder: (m['sort_order'] as num?)?.toDouble() ?? 0,
    isPersonal: (m['is_personal'] as num?) == 1,
    createdAt: _time(m['created_at'])!,
    updatedAt: _time(m['updated_at'])!,
    deletedAt: _time(m['deleted_at']),
  );
}

class Subtask extends Record {
  Subtask({
    required this.id,
    required this.taskId,
    required this.title,
    this.done = false,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  final String id;
  String taskId;
  String title;
  bool done;
  double sortOrder;
  DateTime createdAt;
  @override
  DateTime updatedAt;
  @override
  DateTime? deletedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'task_id': taskId,
    'title': title,
    'done': done ? 1 : 0,
    'sort_order': sortOrder,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
  };

  factory Subtask.fromMap(Map<String, Object?> m) => Subtask(
    id: m['id'] as String,
    taskId: m['task_id'] as String,
    title: m['title'] as String? ?? '',
    done: (m['done'] as num?) == 1,
    sortOrder: (m['sort_order'] as num?)?.toDouble() ?? 0,
    createdAt: _time(m['created_at'])!,
    updatedAt: _time(m['updated_at'])!,
    deletedAt: _time(m['deleted_at']),
  );
}

/// One line in the session list: what you plan to do in this sitting.
/// Kept in its own table, apart from company tasks.
class SessionItem extends Record {
  SessionItem({
    required this.id,
    required this.title,
    this.done = false,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.doneAt,
    this.deletedAt,
  });

  @override
  final String id;
  String title;
  bool done;
  double sortOrder;
  DateTime createdAt;
  @override
  DateTime updatedAt;
  DateTime? doneAt;
  @override
  DateTime? deletedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'done': done ? 1 : 0,
    'sort_order': sortOrder,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'done_at': doneAt?.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
  };

  factory SessionItem.fromMap(Map<String, Object?> m) => SessionItem(
    id: m['id'] as String,
    title: m['title'] as String? ?? '',
    done: (m['done'] as num?) == 1,
    sortOrder: (m['sort_order'] as num?)?.toDouble() ?? 0,
    createdAt: _time(m['created_at'])!,
    updatedAt: _time(m['updated_at'])!,
    doneAt: _time(m['done_at']),
    deletedAt: _time(m['deleted_at']),
  );
}

/// A timestamped progress note ("Sent draft to client").
class TaskUpdate extends Record {
  TaskUpdate({
    required this.id,
    required this.taskId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  final String id;
  String taskId;
  String body;
  DateTime createdAt;
  @override
  DateTime updatedAt;
  @override
  DateTime? deletedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'task_id': taskId,
    'body': body,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
  };

  factory TaskUpdate.fromMap(Map<String, Object?> m) => TaskUpdate(
    id: m['id'] as String,
    taskId: m['task_id'] as String,
    body: m['body'] as String? ?? '',
    createdAt: _time(m['created_at'])!,
    updatedAt: _time(m['updated_at'])!,
    deletedAt: _time(m['deleted_at']),
  );
}

class Task extends Record {
  Task({
    required this.id,
    required this.companyId,
    required this.title,
    this.description = '',
    this.notes = '',
    this.priority = Priority.normal,
    this.status = TaskStatus.todo,
    this.dueDate,
    this.dueMinutes,
    this.expectedDate,
    List<String>? tags,
    required this.sortOrder,
    this.recurrence = Recurrence.none,
    this.timeSpentSeconds = 0,
    this.timerStartedAt,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.archivedAt,
    this.deletedAt,
  }) : tags = tags ?? [];

  @override
  final String id;
  String companyId;
  String title;
  String description;
  String notes;
  Priority priority;
  TaskStatus status;

  /// Calendar date (local midnight) the task is due, if any.
  DateTime? dueDate;

  /// Optional due time as minutes after midnight.
  int? dueMinutes;

  /// When an in-progress task is expected to be finished.
  DateTime? expectedDate;
  List<String> tags;
  double sortOrder;
  Recurrence recurrence;
  int timeSpentSeconds;
  DateTime? timerStartedAt;
  DateTime createdAt;
  @override
  DateTime updatedAt;
  DateTime? startedAt;
  DateTime? completedAt;
  DateTime? archivedAt;
  @override
  DateTime? deletedAt;

  /// Loaded alongside the task; persisted in their own tables.
  List<Subtask> subtasks = [];
  List<TaskUpdate> updates = [];

  bool get isOpen => status != TaskStatus.done;
  bool get isDone => status == TaskStatus.done;
  bool get isArchived => archivedAt != null;
  bool get isUrgent => priority == Priority.urgent;
  bool get hasDueTime => dueDate != null && dueMinutes != null;
  bool get isTimerRunning => timerStartedAt != null;

  List<Subtask> get liveSubtasks =>
      subtasks.where((s) => !s.isDeleted).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<TaskUpdate> get liveUpdates =>
      updates.where((u) => !u.isDeleted).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// The exact moment the task is due; date-only tasks are due at end of day.
  DateTime? get dueAt {
    final d = dueDate;
    if (d == null) return null;
    if (dueMinutes != null) {
      return DateTime(
        d.year,
        d.month,
        d.day,
        dueMinutes! ~/ 60,
        dueMinutes! % 60,
      );
    }
    return DateTime(d.year, d.month, d.day, 23, 59, 59);
  }

  bool isOverdue(DateTime now) {
    if (!isOpen || dueDate == null) return false;
    if (dueMinutes != null) return now.isAfter(dueAt!);
    return daysBetween(now, dueDate!) < 0;
  }

  bool isDueOn(DateTime day) => dueDate != null && sameDay(dueDate!, day);

  Duration timeSpent(DateTime now) {
    var seconds = timeSpentSeconds;
    if (timerStartedAt != null) {
      seconds += now.difference(timerStartedAt!).inSeconds.clamp(0, 1 << 31);
    }
    return Duration(seconds: seconds);
  }

  Task copyAsNew({
    required String id,
    required DateTime now,
    required double sortOrder,
  }) => Task(
    id: id,
    companyId: companyId,
    title: title,
    description: description,
    notes: notes,
    priority: priority,
    status: TaskStatus.todo,
    dueDate: dueDate,
    dueMinutes: dueMinutes,
    expectedDate: null,
    tags: List.of(tags),
    sortOrder: sortOrder,
    recurrence: recurrence,
    createdAt: now,
    updatedAt: now,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'company_id': companyId,
    'title': title,
    'description': description,
    'notes': notes,
    'priority': priority.key,
    'status': status.key,
    'due_date': dueDate == null ? null : ymd(dueDate!),
    'due_minutes': dueMinutes,
    'expected_date': expectedDate == null ? null : ymd(expectedDate!),
    'tags': tags.join('\u001f'),
    'sort_order': sortOrder,
    'recurrence': recurrence.key,
    'time_spent_sec': timeSpentSeconds,
    'timer_started_at': timerStartedAt?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'started_at': startedAt?.millisecondsSinceEpoch,
    'completed_at': completedAt?.millisecondsSinceEpoch,
    'archived_at': archivedAt?.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
  };

  factory Task.fromMap(Map<String, Object?> m) {
    final tagString = m['tags'] as String? ?? '';
    return Task(
      id: m['id'] as String,
      companyId: m['company_id'] as String,
      title: m['title'] as String? ?? '',
      description: m['description'] as String? ?? '',
      notes: m['notes'] as String? ?? '',
      priority: Priority.parse(m['priority'] as String?),
      status: TaskStatus.parse(m['status'] as String?),
      dueDate: parseYmd(m['due_date'] as String?),
      dueMinutes: (m['due_minutes'] as num?)?.toInt(),
      expectedDate: parseYmd(m['expected_date'] as String?),
      tags: tagString.isEmpty ? [] : tagString.split('\u001f'),
      sortOrder: (m['sort_order'] as num?)?.toDouble() ?? 0,
      recurrence: Recurrence.parse(m['recurrence'] as String?),
      timeSpentSeconds: (m['time_spent_sec'] as num?)?.toInt() ?? 0,
      timerStartedAt: _time(m['timer_started_at']),
      createdAt: _time(m['created_at'])!,
      updatedAt: _time(m['updated_at'])!,
      startedAt: _time(m['started_at']),
      completedAt: _time(m['completed_at']),
      archivedAt: _time(m['archived_at']),
      deletedAt: _time(m['deleted_at']),
    );
  }
}

DateTime? _time(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

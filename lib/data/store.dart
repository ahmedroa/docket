import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../l10n/l10n.dart';
import 'models.dart';
import 'persistence.dart';
import 'settings.dart';

/// Undo information for a status change (completing can spawn the next
/// occurrence of a recurring task).
class StatusChange {
  StatusChange(
    this.task,
    this.previousStatus,
    this.previousStartedAt,
    this.previousCompletedAt,
    this.spawned,
  );
  final Task task;
  final TaskStatus previousStatus;
  final DateTime? previousStartedAt;
  final DateTime? previousCompletedAt;
  final Task? spawned;
}

class ImportResult {
  ImportResult(this.added, this.updated);
  final int added;
  final int updated;
}

/// Default palette and icons for the first launch.
class CompanyDefaults {
  static const palette = <int>[
    0xFF4C6EF5, // indigo blue
    0xFF12B886, // teal
    0xFFF59F00, // amber
    0xFF7950F2, // violet
    0xFFE64980, // pink
    0xFF15AABF, // cyan
    0xFF40C057, // green
    0xFFFD7E14, // orange
    0xFFBE4BDB, // grape
    0xFF868E96, // gray
  ];
}

/// Single source of truth. All data is held in memory (it is small) and every
/// mutation is written through to [Persistence] immediately, in order.
class TaskStore extends ChangeNotifier {
  TaskStore(this._persistence, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Persistence _persistence;
  final DateTime Function() _clock;
  DateTime get now => _clock();

  final Map<String, Company> _companies = {};
  final Map<String, Task> _tasks = {};
  final Map<String, SessionItem> _session = {};
  AppSettings settings = AppSettings();
  bool loaded = false;

  /// Last persistence failure, surfaced to the UI.
  final ValueNotifier<Object?> writeError = ValueNotifier(null);

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    final snapshot = await _persistence.loadAll();
    _applySnapshot(snapshot);
    settings = AppSettings.fromJson(await _persistence.loadSettings());
    if (companies.isEmpty) {
      await _seedCompanies();
    }
    loaded = true;
    notifyListeners();
  }

  void _applySnapshot(Snapshot snapshot) {
    _companies
      ..clear()
      ..addEntries(snapshot.companies.map((c) => MapEntry(c.id, c)));
    _tasks
      ..clear()
      ..addEntries(snapshot.tasks.map((t) => MapEntry(t.id, t)));
    for (final s in snapshot.subtasks) {
      _tasks[s.taskId]?.subtasks.add(s);
    }
    for (final u in snapshot.updates) {
      _tasks[u.taskId]?.updates.add(u);
    }
    _session
      ..clear()
      ..addEntries(snapshot.sessionItems.map((i) => MapEntry(i.id, i)));
  }

  Future<void> _seedCompanies() async {
    final t = now;
    final seeds = [
      ('Company A', 0xFF4C6EF5, 'apartment', false),
      ('Company B', 0xFF12B886, 'storefront', false),
      ('Company C', 0xFFF59F00, 'rocket', false),
      ('Personal', 0xFF7950F2, 'person', true),
    ];
    final changes = ChangeSet();
    for (var i = 0; i < seeds.length; i++) {
      final (name, color, icon, personal) = seeds[i];
      final c = Company(
        id: newId(),
        name: tr(name),
        color: color,
        icon: icon,
        sortOrder: i.toDouble(),
        isPersonal: personal,
        createdAt: t,
        updatedAt: t,
      );
      _companies[c.id] = c;
      changes.companies.add(c);
    }
    _enqueue(changes);
    await flush();
  }

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  List<Company> get companies =>
      _companies.values.where((c) => !c.isDeleted).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Company? company(String? id) {
    final c = _companies[id];
    return c == null || c.isDeleted ? null : c;
  }

  Company get personal =>
      companies.firstWhere((c) => c.isPersonal, orElse: () => companies.first);

  /// Every task that isn't deleted, including archived ones.
  Iterable<Task> get allTasks => _tasks.values.where((t) => !t.isDeleted);

  /// Tasks shown in normal views: not deleted, not archived, company exists.
  Iterable<Task> get activeTasks => _tasks.values.where(
    (t) => !t.isDeleted && !t.isArchived && company(t.companyId) != null,
  );

  Task? task(String? id) {
    final t = _tasks[id];
    return t == null || t.isDeleted ? null : t;
  }

  List<String> get allTags {
    final counts = <String, int>{};
    for (final t in activeTasks) {
      for (final tag in t.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  // ---------------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------------

  ChangeSet? _pending;
  Future<void>? _draining;

  void _enqueue(ChangeSet changes) {
    (_pending ??= ChangeSet()).addAll(changes);
    _draining ??= _drain();
  }

  Future<void> _drain() async {
    var attempt = 0;
    try {
      while (_pending != null) {
        final batch = _pending!;
        _pending = null;
        try {
          await _persistence.write(batch);
          writeError.value = null;
          attempt = 0;
        } catch (e) {
          // Keep the data in memory and retry; never drop a change silently.
          writeError.value = e;
          (_pending ??= ChangeSet()).addAll(batch);
          attempt++;
          await Future<void>.delayed(
            Duration(milliseconds: 200 * attempt.clamp(1, 25)),
          );
        }
      }
    } finally {
      _draining = null;
    }
  }

  /// Resolves once every change made so far is on disk.
  Future<void> flush() async {
    while (_draining != null) {
      await _draining;
    }
  }

  void _commit(ChangeSet changes) {
    notifyListeners();
    _enqueue(changes);
  }

  ChangeSet _taskChange(Task t) => ChangeSet()..tasks.add(t);

  Future<void> _settingsWrite = Future.value();

  /// [persist] false applies a change live (e.g. while dragging a slider)
  /// without writing it; the final value is saved with persist true.
  void updateSettings(
    void Function(AppSettings s) edit, {
    bool persist = true,
  }) {
    edit(settings);
    notifyListeners();
    if (!persist) return;
    final json = settings.toJson();
    _settingsWrite = _settingsWrite
        .then((_) => _persistence.saveSettings(json))
        .catchError((Object e) => writeError.value = e);
  }

  Future<void> flushSettings() => _settingsWrite;

  // ---------------------------------------------------------------------------
  // Companies
  // ---------------------------------------------------------------------------

  Company addCompany({
    required String name,
    required int color,
    required String icon,
  }) {
    final t = now;
    final list = companies;
    // New companies go above Personal, which stays last.
    final personalIndex = list.indexWhere((c) => c.isPersonal);
    double order;
    if (personalIndex <= 0) {
      order = list.isEmpty ? 0 : list.last.sortOrder + 1;
    } else {
      order =
          (list[personalIndex - 1].sortOrder + list[personalIndex].sortOrder) /
          2;
    }
    final c = Company(
      id: newId(),
      name: name.trim().isEmpty ? tr('New Company') : name.trim(),
      color: color,
      icon: icon,
      sortOrder: order,
      createdAt: t,
      updatedAt: t,
    );
    _companies[c.id] = c;
    _commit(ChangeSet()..companies.add(c));
    return c;
  }

  void updateCompany(Company c, {String? name, int? color, String? icon}) {
    if (name != null && name.trim().isNotEmpty) c.name = name.trim();
    if (color != null) c.color = color;
    if (icon != null) c.icon = icon;
    c.updatedAt = now;
    _commit(ChangeSet()..companies.add(c));
  }

  /// Untouched default names ("Company A" / "الشركة الأولى") follow the
  /// interface language; anything the user typed is left alone.
  /// Off in demo mode, where the sample names stay as written.
  bool localizeNames = true;

  /// Default names ("Company A", "Personal"…) follow the language and the
  /// companies/projects wording until the user renames them.
  void localizeDefaultNames(AppLanguage lang) {
    const defaults = [
      'Company A',
      'Company B',
      'Company C',
      'Personal',
      'New Company',
    ];
    if (!localizeNames) return;
    for (final c in companies) {
      for (final en in defaults) {
        if (defaultNameVariants(en).contains(c.name)) {
          final target = trIn(lang, en);
          if (c.name != target) updateCompany(c, name: target);
          break;
        }
      }
    }
  }

  void moveCompany(int oldIndex, int newIndex) {
    final list = companies;
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final c = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), c);
    final changes = ChangeSet();
    final t = now;
    for (var i = 0; i < list.length; i++) {
      if (list[i].sortOrder != i.toDouble()) {
        list[i].sortOrder = i.toDouble();
        list[i].updatedAt = t;
        changes.companies.add(list[i]);
      }
    }
    _commit(changes);
  }

  /// Deletes a company. Its tasks move to [moveTasksTo], or are deleted with it.
  void deleteCompany(Company c, {String? moveTasksTo}) {
    if (c.isPersonal) return;
    final t = now;
    final changes = ChangeSet();
    final target = company(moveTasksTo);
    for (final task in _tasks.values.where(
      (x) => x.companyId == c.id && !x.isDeleted,
    )) {
      if (target != null) {
        task.companyId = target.id;
      } else {
        task.deletedAt = t;
      }
      task.updatedAt = t;
      changes.tasks.add(task);
    }
    c.deletedAt = t;
    c.updatedAt = t;
    changes.companies.add(c);
    _commit(changes);
  }

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  /// A blank, unsaved task for the editor.
  Task draftTask({String? companyId}) {
    final t = now;
    return Task(
      id: newId(),
      companyId: company(companyId)?.id ?? companies.first.id,
      title: '',
      sortOrder: 0,
      createdAt: t,
      updatedAt: t,
    );
  }

  double _topSortOrder(String companyId) {
    var min = 0.0;
    var any = false;
    for (final t in _tasks.values) {
      if (t.companyId == companyId && !t.isDeleted) {
        if (!any || t.sortOrder < min) min = t.sortOrder;
        any = true;
      }
    }
    return any ? min - 1 : 0;
  }

  /// Saves a new task (from the editor or quick add). New tasks go to the top.
  Task addTask(Task draft, {List<String> subtasks = const []}) {
    final t = now;
    draft
      ..title = draft.title.trim()
      ..sortOrder = _topSortOrder(draft.companyId)
      ..createdAt = t
      ..updatedAt = t;
    if (draft.status == TaskStatus.inProgress) draft.startedAt ??= t;
    if (draft.status == TaskStatus.done) draft.completedAt ??= t;
    _tasks[draft.id] = draft;
    final changes = _taskChange(draft);
    var order = 0.0;
    for (final title
        in subtasks.map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      final s = Subtask(
        id: newId(),
        taskId: draft.id,
        title: title,
        sortOrder: order++,
        createdAt: t,
        updatedAt: t,
      );
      draft.subtasks.add(s);
      changes.subtasks.add(s);
    }
    _commit(changes);
    return draft;
  }

  /// Quick add: title (with inline `!` for urgent and `#tags`), company and optional due date.
  Task quickAdd(
    String input, {
    required String companyId,
    DateTime? due,
    Priority? priority,
  }) {
    final parsed = parseQuickInput(input);
    final draft = draftTask(companyId: companyId)
      ..title = parsed.title
      ..priority = priority ?? parsed.priority
      ..tags = parsed.tags
      ..dueDate = due == null ? null : dateOnly(due);
    return addTask(draft);
  }

  void updateTask(Task t, void Function(Task t) edit) {
    edit(t);
    t.updatedAt = now;
    _commit(_taskChange(t));
  }

  StatusChange? setStatus(Task t, TaskStatus status) {
    if (t.status == status) return null;
    final change = StatusChange(t, t.status, t.startedAt, t.completedAt, null);
    final time = now;
    Task? spawned;
    final changes = _taskChange(t);

    if (status == TaskStatus.inProgress) {
      t.startedAt ??= time;
      t.completedAt = null;
    } else if (status == TaskStatus.done) {
      t.completedAt = time;
      _stopTimer(t, time);
      if (t.recurrence != Recurrence.none) {
        spawned = _spawnNext(t, time, changes);
      }
    } else {
      t.completedAt = null;
    }
    t.status = status;
    t.updatedAt = time;
    _commit(changes);
    return StatusChange(
      change.task,
      change.previousStatus,
      change.previousStartedAt,
      change.previousCompletedAt,
      spawned,
    );
  }

  Task _spawnNext(Task t, DateTime time, ChangeSet changes) {
    final base = t.dueDate ?? dateOnly(time);
    var next = t.recurrence.next(base);
    // Catch up if the task was finished late, so the next one isn't already overdue.
    while (daysBetween(time, next) < 0) {
      next = t.recurrence.next(next);
    }
    final n = t.copyAsNew(
      id: newId(),
      now: time,
      sortOrder: _topSortOrder(t.companyId),
    )..dueDate = next;
    var order = 0.0;
    for (final s in t.liveSubtasks) {
      final copy = Subtask(
        id: newId(),
        taskId: n.id,
        title: s.title,
        sortOrder: order++,
        createdAt: time,
        updatedAt: time,
      );
      n.subtasks.add(copy);
      changes.subtasks.add(copy);
    }
    _tasks[n.id] = n;
    changes.tasks.add(n);
    return n;
  }

  void undoStatus(StatusChange change) {
    final t = change.task;
    final time = now;
    final changes = _taskChange(t);
    t
      ..status = change.previousStatus
      ..startedAt = change.previousStartedAt
      ..completedAt = change.previousCompletedAt
      ..updatedAt = time;
    final spawned = change.spawned;
    if (spawned != null) {
      spawned
        ..deletedAt = time
        ..updatedAt = time;
      changes.tasks.add(spawned);
    }
    _commit(changes);
  }

  void setPriority(Task t, Priority p) {
    if (t.priority == p) return;
    updateTask(t, (t) => t.priority = p);
  }

  void moveToCompany(Task t, String companyId) {
    if (t.companyId == companyId || company(companyId) == null) return;
    updateTask(t, (t) {
      t.companyId = companyId;
      t.sortOrder = _topSortOrder(companyId);
    });
  }

  Task duplicate(Task t) {
    final time = now;
    final copy =
        t.copyAsNew(id: newId(), now: time, sortOrder: t.sortOrder - 0.5)
          ..status = t.status == TaskStatus.done ? TaskStatus.todo : t.status
          ..recurrence = t.recurrence;
    if (copy.status == TaskStatus.inProgress) copy.startedAt = time;
    final changes = _taskChange(copy);
    var order = 0.0;
    for (final s in t.liveSubtasks) {
      final sc = Subtask(
        id: newId(),
        taskId: copy.id,
        title: s.title,
        done: false,
        sortOrder: order++,
        createdAt: time,
        updatedAt: time,
      );
      copy.subtasks.add(sc);
      changes.subtasks.add(sc);
    }
    _tasks[copy.id] = copy;
    _commit(changes);
    return copy;
  }

  void setArchived(Task t, bool archived) {
    updateTask(t, (t) => t.archivedAt = archived ? now : null);
  }

  void delete(Task t) {
    final time = now;
    _stopTimer(t, time);
    updateTask(t, (t) => t.deletedAt = time);
  }

  /// Undo for [delete]: deleted tasks are tombstones until purged.
  void restore(Task t) {
    t.deletedAt = null;
    t.updatedAt = now;
    _commit(_taskChange(t));
  }

  /// Moves the task at [oldIndex] of [ordered] so it ends up at [newIndex],
  /// rewriting as few sort orders as possible.
  void reorder(List<Task> ordered, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    final list = List.of(ordered);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), moved);
    final i = list.indexOf(moved);
    final before = i > 0 ? list[i - 1].sortOrder : null;
    final after = i < list.length - 1 ? list[i + 1].sortOrder : null;
    double order;
    if (before == null && after == null) {
      order = 0;
    } else if (before == null) {
      order = after! - 1;
    } else if (after == null) {
      order = before + 1;
    } else {
      order = (before + after) / 2;
    }
    // Neighbours collide when the list was never manually ordered: renumber all.
    if ((before != null && order <= before) ||
        (after != null && order >= after) ||
        (before != null && after != null && (after - before).abs() < 1e-9)) {
      final changes = ChangeSet();
      final time = now;
      for (var k = 0; k < list.length; k++) {
        list[k]
          ..sortOrder = k.toDouble()
          ..updatedAt = time;
        changes.tasks.add(list[k]);
      }
      _commit(changes);
      return;
    }
    updateTask(moved, (t) => t.sortOrder = order);
  }

  // Batch operations -----------------------------------------------------------

  List<StatusChange> setStatusMany(Iterable<Task> tasks, TaskStatus status) => [
    for (final t in tasks.toList()) ?setStatus(t, status),
  ];

  void setPriorityMany(Iterable<Task> tasks, Priority p) {
    for (final t in tasks.toList()) {
      setPriority(t, p);
    }
  }

  void moveMany(Iterable<Task> tasks, String companyId) {
    for (final t in tasks.toList()) {
      moveToCompany(t, companyId);
    }
  }

  void deleteMany(Iterable<Task> tasks) {
    for (final t in tasks.toList()) {
      delete(t);
    }
  }

  void restoreMany(Iterable<Task> tasks) {
    for (final t in tasks.toList()) {
      restore(t);
    }
  }

  void archiveMany(Iterable<Task> tasks, bool archived) {
    for (final t in tasks.toList()) {
      setArchived(t, archived);
    }
  }

  // Subtasks ----------------------------------------------------------------------

  Subtask addSubtask(Task t, String title) {
    final time = now;
    final live = t.liveSubtasks;
    final s = Subtask(
      id: newId(),
      taskId: t.id,
      title: title.trim(),
      sortOrder: live.isEmpty ? 0 : live.last.sortOrder + 1,
      createdAt: time,
      updatedAt: time,
    );
    t.subtasks.add(s);
    t.updatedAt = time;
    _commit(
      ChangeSet()
        ..subtasks.add(s)
        ..tasks.add(t),
    );
    return s;
  }

  void _touchSubtask(Task t, Subtask s) {
    final time = now;
    s.updatedAt = time;
    t.updatedAt = time;
    _commit(
      ChangeSet()
        ..subtasks.add(s)
        ..tasks.add(t),
    );
  }

  void toggleSubtask(Task t, Subtask s) {
    s.done = !s.done;
    _touchSubtask(t, s);
  }

  void renameSubtask(Task t, Subtask s, String title) {
    if (title.trim().isEmpty) return;
    s.title = title.trim();
    _touchSubtask(t, s);
  }

  void deleteSubtask(Task t, Subtask s) {
    s.deletedAt = now;
    _touchSubtask(t, s);
  }

  void reorderSubtasks(Task t, int oldIndex, int newIndex) {
    final list = t.liveSubtasks;
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final s = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), s);
    final time = now;
    final changes = ChangeSet()..tasks.add(t);
    for (var i = 0; i < list.length; i++) {
      list[i]
        ..sortOrder = i.toDouble()
        ..updatedAt = time;
      changes.subtasks.add(list[i]);
    }
    t.updatedAt = time;
    _commit(changes);
  }

  // Session list ------------------------------------------------------------------
  // What you plan to do in this sitting. Separate from company tasks: its own
  // table, no dates, no reminders, not counted anywhere else.

  /// What you're working on first, then the rest in the order written, then
  /// the done ones, newest first.
  List<SessionItem> get sessionItems {
    final live = _session.values.where((i) => !i.isDeleted);
    final open = live.where((i) => !i.done).toList()
      ..sort((a, b) {
        final working = (b.startedAt != null ? 1 : 0).compareTo(
          a.startedAt != null ? 1 : 0,
        );
        return working != 0 ? working : a.sortOrder.compareTo(b.sortOrder);
      });
    final done = live.where((i) => i.done).toList()
      ..sort(
        (a, b) => (b.doneAt ?? b.updatedAt).compareTo(a.doneAt ?? a.updatedAt),
      );
    return [...open, ...done];
  }

  SessionItem? addSessionItem(String title) {
    final text = title.trim();
    if (text.isEmpty) return null;
    final time = now;
    final live = _session.values.where((i) => !i.isDeleted).toList();
    // Writing the first line is when a session starts.
    if (live.isEmpty) {
      updateSettings((s) => s.sessionStartedAt = time);
    }
    final item = SessionItem(
      id: newId(),
      title: text,
      sortOrder: live.isEmpty
          ? 0
          : live.map((i) => i.sortOrder).reduce((a, b) => a > b ? a : b) + 1,
      createdAt: time,
      updatedAt: time,
    );
    _session[item.id] = item;
    _commit(ChangeSet()..sessionItems.add(item));
    return item;
  }

  void _touchSession(Iterable<SessionItem> items) {
    final time = now;
    final changes = ChangeSet();
    for (final i in items) {
      i.updatedAt = time;
      changes.sessionItems.add(i);
    }
    if (!changes.isEmpty) _commit(changes);
  }

  /// The circle, one step per click: to do → working on it → done; a done
  /// item goes back to to do.
  void advanceSessionItem(SessionItem i) {
    final time = now;
    switch (i.status) {
      case TaskStatus.todo:
        i.startedAt = time;
      case TaskStatus.inProgress:
        i
          ..done = true
          ..doneAt = time;
      case TaskStatus.done:
        i
          ..done = false
          ..doneAt = null
          ..startedAt = null;
    }
    _touchSession([i]);
  }

  void renameSessionItem(SessionItem i, String title) {
    final text = title.trim();
    if (text.isEmpty || text == i.title) return;
    i.title = text;
    _touchSession([i]);
  }

  void deleteSessionItem(SessionItem i) {
    i.deletedAt = now;
    _touchSession([i]);
  }

  /// Removes the ticked items; returns them for undo.
  List<SessionItem> clearCompletedSession() {
    final done = sessionItems.where((i) => i.done).toList();
    for (final i in done) {
      i.deletedAt = now;
    }
    _touchSession(done);
    return done;
  }

  /// Empties the list for a fresh session; returns what was there and when
  /// it started, for undo.
  (List<SessionItem>, DateTime?) startNewSession() {
    final items = sessionItems;
    final started = settings.sessionStartedAt;
    for (final i in items) {
      i.deletedAt = now;
    }
    updateSettings((s) => s.sessionStartedAt = null);
    _touchSession(items);
    return (items, started);
  }

  void restoreSessionItems(List<SessionItem> items, {DateTime? startedAt}) {
    for (final i in items) {
      i.deletedAt = null;
    }
    if (startedAt != null) {
      updateSettings((s) => s.sessionStartedAt = startedAt);
    }
    _touchSession(items);
  }

  // Progress updates ------------------------------------------------------------

  TaskUpdate addUpdate(Task t, String body) {
    final time = now;
    final u = TaskUpdate(
      id: newId(),
      taskId: t.id,
      body: body.trim(),
      createdAt: time,
      updatedAt: time,
    );
    t.updates.add(u);
    t.updatedAt = time;
    _commit(
      ChangeSet()
        ..updates.add(u)
        ..tasks.add(t),
    );
    return u;
  }

  void deleteUpdate(Task t, TaskUpdate u) {
    final time = now;
    u
      ..deletedAt = time
      ..updatedAt = time;
    t.updatedAt = time;
    _commit(
      ChangeSet()
        ..updates.add(u)
        ..tasks.add(t),
    );
  }

  // Time tracking -----------------------------------------------------------------

  void startTimer(Task t) {
    final time = now;
    final changes = ChangeSet();
    // One timer at a time.
    for (final other in _tasks.values.where(
      (x) => x.isTimerRunning && x != t,
    )) {
      _stopTimer(other, time);
      other.updatedAt = time;
      changes.tasks.add(other);
    }
    if (!t.isTimerRunning) t.timerStartedAt = time;
    if (t.status == TaskStatus.todo) {
      t.status = TaskStatus.inProgress;
      t.startedAt ??= time;
    }
    t.updatedAt = time;
    changes.tasks.add(t);
    _commit(changes);
  }

  void stopTimer(Task t) {
    if (!t.isTimerRunning) return;
    final time = now;
    _stopTimer(t, time);
    t.updatedAt = time;
    _commit(_taskChange(t));
  }

  void _stopTimer(Task t, DateTime time) {
    final started = t.timerStartedAt;
    if (started == null) return;
    t.timeSpentSeconds += time.difference(started).inSeconds.clamp(0, 1 << 31);
    t.timerStartedAt = null;
  }

  void resetTime(Task t) {
    updateTask(t, (t) {
      t.timeSpentSeconds = 0;
      t.timerStartedAt = null;
    });
  }

  Task? get runningTimer {
    for (final t in activeTasks) {
      if (t.isTimerRunning) return t;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Backup / restore
  // ---------------------------------------------------------------------------

  /// Everything, including tombstones, so a restore also replays deletions.
  Snapshot snapshot() {
    final tasks = _tasks.values.toList();
    return Snapshot(
      companies: _companies.values.toList(),
      tasks: tasks,
      subtasks: [for (final t in tasks) ...t.subtasks],
      updates: [for (final t in tasks) ...t.updates],
      sessionItems: _session.values.toList(),
    );
  }

  /// Replaces all data (restore from backup).
  Future<void> replaceAll(Snapshot snapshot) async {
    await flush();
    await _persistence.replaceAll(snapshot);
    _applySnapshot(await _persistence.loadAll());
    if (companies.isEmpty) await _seedCompanies();
    notifyListeners();
  }

  /// Merges another snapshot: unknown records are added, known ones are
  /// replaced only when the incoming copy is newer.
  Future<ImportResult> merge(Snapshot incoming) async {
    await flush();
    var added = 0;
    var updated = 0;
    final changes = ChangeSet();

    bool take(Record? existing, Record next) {
      if (existing == null) {
        added++;
        return true;
      }
      if (next.updatedAt.isAfter(existing.updatedAt)) {
        updated++;
        return true;
      }
      return false;
    }

    final existingSubtasks = {
      for (final t in _tasks.values)
        for (final s in t.subtasks) s.id: s,
    };
    final existingUpdates = {
      for (final t in _tasks.values)
        for (final u in t.updates) u.id: u,
    };

    for (final c in incoming.companies) {
      if (take(_companies[c.id], c)) changes.companies.add(c);
    }
    for (final t in incoming.tasks) {
      if (take(_tasks[t.id], t)) changes.tasks.add(t);
    }
    for (final s in incoming.subtasks) {
      if (take(existingSubtasks[s.id], s)) changes.subtasks.add(s);
    }
    for (final u in incoming.updates) {
      if (take(existingUpdates[u.id], u)) changes.updates.add(u);
    }
    for (final i in incoming.sessionItems) {
      if (take(_session[i.id], i)) changes.sessionItems.add(i);
    }
    await _persistence.write(changes);
    _applySnapshot(await _persistence.loadAll());
    notifyListeners();
    return ImportResult(added, updated);
  }

  /// Drops tombstones older than 30 days to keep the database small.
  Future<void> purgeOldTombstones() =>
      _persistence.purgeDeleted(now.subtract(const Duration(days: 30)));

  /// Re-renders time-dependent UI (overdue, "today") without data changes.
  void tick() => notifyListeners();
}

/// Result of parsing quick-add text like "Send invoice #finance !".
class QuickInput {
  QuickInput(this.title, this.priority, this.tags);
  final String title;
  final Priority priority;
  final List<String> tags;
}

QuickInput parseQuickInput(String input) {
  var priority = Priority.normal;
  final tags = <String>[];
  final words = <String>[];
  for (final word in input.trim().split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    if (word == '!' || word == '!!' || word == '!urgent') {
      priority = Priority.urgent;
    } else if (word == '!low') {
      priority = Priority.low;
    } else if (word.length > 1 && word.startsWith('#')) {
      final tag = word.substring(1);
      if (!tags.contains(tag)) tags.add(tag);
    } else {
      words.add(word);
    }
  }
  var title = words.join(' ');
  // "Call the bank!" → urgent, keeping the exclamation out of the title.
  if (title.endsWith('!!')) {
    priority = Priority.urgent;
    title = title.substring(0, title.length - 2).trimRight();
  }
  return QuickInput(title, priority, tags);
}

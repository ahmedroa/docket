import '../core/dates.dart';
import '../l10n/l10n.dart';
import 'models.dart';
import 'settings.dart';
import 'store.dart';

class CompanyCounts {
  int todo = 0;
  int inProgress = 0;
  int done = 0;
  int urgent = 0;
  int overdue = 0;
  int get open => todo + inProgress;
}

class Summary {
  int open = 0;
  int urgent = 0;
  int inProgress = 0;
  int overdue = 0;
  int completed = 0;
  int dueToday = 0;
}

/// The built-in lists reachable from the home screen and shortcuts.
enum ListKind {
  all('All Tasks'),
  today('Today'),
  overdue('Overdue'),
  urgent('Urgent'),
  inProgress('In Progress'),
  completed('Completed'),
  week('This Week'),
  archived('Archived');

  const ListKind(this.en);
  final String en;
  String get title => tr(en);
}

/// Search filters. Within a group (companies, statuses) any match passes;
/// the flags must all hold.
class TaskFilter {
  final Set<String> companyIds = {};
  final Set<TaskStatus> statuses = {};
  bool urgent = false;
  bool overdue = false;
  bool today = false;
  bool thisWeek = false;

  bool get isEmpty =>
      companyIds.isEmpty &&
      statuses.isEmpty &&
      !urgent &&
      !overdue &&
      !today &&
      !thisWeek;

  void clear() {
    companyIds.clear();
    statuses.clear();
    urgent = overdue = today = thisWeek = false;
  }
}

extension TaskQueries on TaskStore {
  Iterable<Task> get openTasks => activeTasks.where((t) => t.isOpen);

  Summary summary() {
    final n = now;
    final s = Summary();
    for (final t in activeTasks) {
      if (t.isDone) {
        s.completed++;
        continue;
      }
      s.open++;
      if (t.isUrgent) s.urgent++;
      if (t.status == TaskStatus.inProgress) s.inProgress++;
      if (t.isOverdue(n)) s.overdue++;
      if (t.isDueOn(n)) s.dueToday++;
    }
    return s;
  }

  Map<String, CompanyCounts> countsByCompany() {
    final n = now;
    final map = {for (final c in companies) c.id: CompanyCounts()};
    for (final t in activeTasks) {
      final c = map[t.companyId];
      if (c == null) continue;
      switch (t.status) {
        case TaskStatus.todo:
          c.todo++;
        case TaskStatus.inProgress:
          c.inProgress++;
        case TaskStatus.done:
          c.done++;
      }
      if (t.isOpen && t.isUrgent) c.urgent++;
      if (t.isOverdue(n)) c.overdue++;
    }
    return map;
  }

  /// Number shown next to the menu bar icon.
  int badgeCount(BadgeMode mode) {
    final n = now;
    return switch (mode) {
      BadgeMode.none => 0,
      BadgeMode.attention =>
        openTasks.where((t) => t.isUrgent || t.isOverdue(n)).length,
      BadgeMode.today =>
        openTasks.where((t) => t.isDueOn(n) || t.isOverdue(n)).length,
      BadgeMode.open => openTasks.length,
    };
  }

  /// Due today, overdue, or urgent without a date.
  bool isTodayTask(Task t, DateTime n) {
    if (!t.isOpen) return false;
    if (t.dueDate != null) return daysBetween(n, t.dueDate!) <= 0;
    return t.isUrgent;
  }

  /// Today's list: urgent → overdue → due soon (timed) → the rest.
  List<Task> todayTasks() {
    final n = now;
    return openTasks.where((t) => isTodayTask(t, n)).toList()
      ..sort((a, b) => compareToday(a, b, n));
  }

  /// Completed tasks kept, ticked, at the bottom of [kind]'s list, newest
  /// first. "All" keeps every completed task; the action lists keep what was
  /// finished today and belonged there.
  List<Task> completedFor(ListKind kind) {
    final n = now;
    final bool Function(Task t) belongs = switch (kind) {
      ListKind.all || ListKind.today => (_) => true,
      ListKind.urgent => (t) => t.isUrgent,
      ListKind.inProgress => (t) => t.startedAt != null,
      ListKind.overdue => (t) => wasLate(t),
      ListKind.week => (t) {
        if (t.dueDate == null) return false;
        return daysBetween(startOfWeek(n), t.dueDate!) >= 0 &&
            daysBetween(t.dueDate!, endOfWeek(n)) >= 0;
      },
      ListKind.completed || ListKind.archived => (_) => false,
    };
    return activeTasks
        .where(
          (t) =>
              t.isDone &&
              belongs(t) &&
              (kind == ListKind.all ||
                  (t.completedAt != null && sameDay(t.completedAt!, n))),
        )
        .toList()
      ..sort(compareCompleted);
  }

  /// A company's completed tasks, newest first. [startedOnly] keeps the ones
  /// that went through In Progress.
  List<Task> completedForCompany(
    String companyId, {
    bool startedOnly = false,
  }) =>
      activeTasks
          .where(
            (t) =>
                t.companyId == companyId &&
                t.isDone &&
                (!startedOnly || t.startedAt != null),
          )
          .toList()
        ..sort(compareCompleted);

  List<Task> tasksForCompany(
    String companyId,
    TaskStatus status,
    SortMode sort,
  ) {
    final list = activeTasks
        .where((t) => t.companyId == companyId && t.status == status)
        .toList();
    if (status == TaskStatus.done) {
      list.sort(compareCompleted);
    } else {
      list.sort(comparator(sort));
    }
    return list;
  }

  /// Open tasks of [kind] (all of them for Completed and Archived).
  List<Task> listTasks(ListKind kind, {required SortMode sort}) {
    final n = now;
    switch (kind) {
      case ListKind.today:
        return todayTasks();
      case ListKind.completed:
        return activeTasks.where((t) => t.isDone).toList()
          ..sort(compareCompleted);
      case ListKind.archived:
        return allTasks
            .where((t) => t.isArchived && company(t.companyId) != null)
            .toList()
          ..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));
      case ListKind.overdue:
        return openTasks.where((t) => t.isOverdue(n)).toList()..sort((a, b) {
          final p = a.priority.rank.compareTo(b.priority.rank);
          return p != 0 ? p : a.dueAt!.compareTo(b.dueAt!);
        });
      case ListKind.urgent:
        return openTasks.where((t) => t.isUrgent).toList()
          ..sort(comparator(SortMode.dueDate));
      case ListKind.inProgress:
        return openTasks
            .where((t) => t.status == TaskStatus.inProgress)
            .toList()
          ..sort(comparator(sort));
      case ListKind.week:
        final start = startOfWeek(n);
        final end = endOfWeek(n);
        return openTasks
            .where(
              (t) =>
                  t.dueDate != null &&
                  daysBetween(start, t.dueDate!) >= 0 &&
                  daysBetween(t.dueDate!, end) >= 0,
            )
            .toList()
          ..sort(comparator(SortMode.dueDate));
      case ListKind.all:
        return openTasks.toList()..sort(comparator(sort));
    }
  }

  List<Task> search(
    String query,
    TaskFilter filter, {
    bool includeArchived = false,
  }) {
    final n = now;
    final tokens = normalizeForSearch(query)
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final source = includeArchived ? allTasks : activeTasks;
    final results = <Task>[];
    for (final t in source) {
      final c = company(t.companyId);
      if (c == null) continue;
      if (filter.companyIds.isNotEmpty &&
          !filter.companyIds.contains(t.companyId)) {
        continue;
      }
      if (filter.statuses.isNotEmpty && !filter.statuses.contains(t.status)) {
        continue;
      }
      if (filter.urgent && !(t.isUrgent && t.isOpen)) continue;
      if (filter.overdue && !t.isOverdue(n)) continue;
      if (filter.today && !t.isDueOn(n)) continue;
      if (filter.thisWeek) {
        final d = t.dueDate;
        if (d == null ||
            daysBetween(startOfWeek(n), d) < 0 ||
            daysBetween(d, endOfWeek(n)) < 0) {
          continue;
        }
      }
      if (tokens.isNotEmpty) {
        final hay = searchText(t, c, n);
        if (!tokens.every(hay.contains)) continue;
      }
      results.add(t);
    }
    results.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      if (a.isDone && b.isDone) return compareCompleted(a, b);
      return comparator(SortMode.priority)(a, b);
    });
    return results;
  }

  /// Every searchable fact about a task, normalised.
  String searchText(Task t, Company c, DateTime n) {
    final b = StringBuffer()
      ..writeln(t.title)
      ..writeln(t.description)
      ..writeln(t.notes)
      ..writeln(c.name)
      // Both languages, so "urgent" and "عاجلة" find the same tasks.
      ..writeln('${t.priority.en} ${trIn(AppLanguage.ar, t.priority.en)}')
      ..writeln('${t.status.en} ${trIn(AppLanguage.ar, t.status.en)}')
      ..writeln(
        t.status == TaskStatus.done ? 'done completed منجزة' : 'open مفتوحة',
      )
      ..writeln(
        t.status == TaskStatus.todo ? 'todo to-do required المطلوبة' : '',
      );
    for (final tag in t.tags) {
      b.writeln('#$tag $tag');
    }
    final d = t.dueDate;
    if (d != null) {
      b
        ..writeln(ymd(d))
        ..writeln(
          '${d.day} ${monthsShortIn(AppLanguage.en)[d.month - 1]} '
          '${monthsLongIn(AppLanguage.en)[d.month - 1]} ${monthsLongIn(AppLanguage.ar)[d.month - 1]}',
        )
        ..writeln(
          '${weekdaysLongIn(AppLanguage.en)[d.weekday - 1]} ${weekdaysLongIn(AppLanguage.ar)[d.weekday - 1]}',
        )
        ..writeln(formatRelativeDay(d, n, lang: AppLanguage.en))
        ..writeln(formatRelativeDay(d, n, lang: AppLanguage.ar));
    }
    if (t.isOverdue(n)) b.writeln('overdue late متأخرة');
    if (t.recurrence != Recurrence.none) {
      b.writeln(
        'repeat recurring ${t.recurrence.en} تكرار ${trIn(AppLanguage.ar, t.recurrence.en)}',
      );
    }
    for (final s in t.liveSubtasks) {
      b.writeln(s.title);
    }
    for (final u in t.liveUpdates) {
      b.writeln(u.body);
    }
    return normalizeForSearch(b.toString());
  }
}

/// Today ordering: urgent first, then overdue, then timed tasks by time, then the rest.
int compareToday(Task a, Task b, DateTime n) {
  int group(Task t) {
    if (t.isUrgent) return 0;
    if (t.isOverdue(n)) return 1;
    if (t.hasDueTime) return 2;
    return 3 + t.priority.rank;
  }

  final g = group(a).compareTo(group(b));
  if (g != 0) return g;
  final da = a.dueAt;
  final db = b.dueAt;
  if (da != null && db != null && da != db) return da.compareTo(db);
  if (da != null && db == null) return -1;
  if (da == null && db != null) return 1;
  return a.sortOrder.compareTo(b.sortOrder);
}

/// Finished after its due date (or due day).
bool wasLate(Task t) {
  final done = t.completedAt;
  if (done == null || t.dueDate == null) return false;
  if (t.dueMinutes != null) return done.isAfter(t.dueAt!);
  return daysBetween(done, t.dueDate!) < 0;
}

int compareCompleted(Task a, Task b) {
  final ca = a.completedAt ?? a.updatedAt;
  final cb = b.completedAt ?? b.updatedAt;
  return cb.compareTo(ca);
}

int Function(Task, Task) comparator(SortMode mode) {
  int manual(Task a, Task b) {
    final o = a.sortOrder.compareTo(b.sortOrder);
    return o != 0 ? o : b.createdAt.compareTo(a.createdAt);
  }

  int due(Task a, Task b) {
    final da = a.dueAt;
    final db = b.dueAt;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  return switch (mode) {
    SortMode.manual => manual,
    SortMode.priority => (a, b) {
      final p = a.priority.rank.compareTo(b.priority.rank);
      if (p != 0) return p;
      final d = due(a, b);
      return d != 0 ? d : manual(a, b);
    },
    SortMode.dueDate => (a, b) {
      final d = due(a, b);
      if (d != 0) return d;
      final p = a.priority.rank.compareTo(b.priority.rank);
      return p != 0 ? p : manual(a, b);
    },
    SortMode.created => (a, b) => b.createdAt.compareTo(a.createdAt),
  };
}

final _diacritics = RegExp('[ً-ْٰـ]');

/// Lower-cases and folds Arabic letter variants so "مهمة" finds "مهمه" and "أحمد" finds "احمد".
String normalizeForSearch(String s) => s
    .toLowerCase()
    .replaceAll(_diacritics, '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي');

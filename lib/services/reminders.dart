import 'dart:async';

import '../core/dates.dart';
import '../core/native.dart';
import '../data/models.dart';
import '../data/queries.dart';
import '../data/store.dart';
import '../l10n/l10n.dart';

/// One scheduled macOS notification.
class PlannedNotification {
  PlannedNotification(this.id, this.at, this.title, this.body, [this.taskId]);
  final String id;
  final DateTime at;
  final String title;
  final String body;
  final String? taskId;

  Map<String, Object?> toMap() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'body': body,
    'taskId': taskId ?? '',
  };

  @override
  String toString() => '$id @ $at: $title — $body';
}

/// Computes the full notification schedule from the data and hands it to
/// macOS. Re-planned whenever data or settings change, and every 15 minutes
/// so the morning summary always reflects the current state.
class ReminderService {
  ReminderService(this.store, {Native? native})
    : _native = native ?? Native.instance;

  final TaskStore store;
  final Native _native;
  Timer? _debounce;
  Timer? _periodic;
  String _lastSignature = '';

  /// Upper bound per sync; macOS keeps a limited number of pending requests.
  static const maxPending = 60;

  void start() {
    store.addListener(_schedule);
    _periodic = Timer.periodic(const Duration(minutes: 15), (_) => sync());
    sync();
  }

  void dispose() {
    store.removeListener(_schedule);
    _debounce?.cancel();
    _periodic?.cancel();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), sync);
  }

  Future<void> sync() async {
    final s = store.settings;
    final items = s.notificationsEnabled
        ? plan(store, store.now)
        : <PlannedNotification>[];
    final signature = items
        .map((i) => '${i.id}|${i.at.millisecondsSinceEpoch}|${i.body}')
        .join(';');
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    await _native.scheduleNotifications(items.map((i) => i.toMap()).toList());
  }

  /// Pure planning function (unit-tested).
  static List<PlannedNotification> plan(TaskStore store, DateTime now) {
    final s = store.settings;
    final out = <PlannedNotification>[];
    final horizon = now.add(const Duration(days: 14));

    String companyName(Task t) => store.company(t.companyId)?.name ?? '';
    String timeLabel(Task t) =>
        t.hasDueTime ? formatTimeOfDay(t.dueMinutes!, use24h: s.use24h) : '';

    for (final t in store.openTasks) {
      final d = t.dueDate;
      if (d == null) continue;
      final urgentPrefix = t.isUrgent ? tr('Urgent · ') : '';

      if (t.hasDueTime) {
        final due = t.dueAt!;
        if (s.notifyAtDue && due.isAfter(now) && due.isBefore(horizon)) {
          out.add(
            PlannedNotification(
              'due-${t.id}',
              due,
              t.title,
              '$urgentPrefix${tr('Due now · {company}', {'company': companyName(t)})}',
              t.id,
            ),
          );
        }
        if (s.remindBefore > 0) {
          final pre = due.subtract(Duration(minutes: s.remindBefore));
          if (pre.isAfter(now) && pre.isBefore(horizon)) {
            final lead = s.remindBefore >= 1440
                ? tr('Due tomorrow at {time}', {'time': timeLabel(t)})
                : tr('Due in {duration} ({time})', {
                    'duration': formatDuration(
                      Duration(minutes: s.remindBefore),
                    ),
                    'time': timeLabel(t),
                  });
            out.add(
              PlannedNotification(
                'pre-${t.id}',
                pre,
                t.title,
                '$urgentPrefix$lead · ${companyName(t)}',
                t.id,
              ),
            );
          }
        }
      } else {
        // Date-only tasks: remind on the morning of the due date.
        final at = DateTime(
          d.year,
          d.month,
          d.day,
          s.digestMinutes ~/ 60,
          s.digestMinutes % 60,
        );
        if (s.notifyAtDue && at.isAfter(now) && at.isBefore(horizon)) {
          out.add(
            PlannedNotification(
              'due-${t.id}',
              at,
              t.title,
              '$urgentPrefix${tr('Due today · {company}', {'company': companyName(t)})}',
              t.id,
            ),
          );
        }
        if (s.remindBefore >= 1440) {
          final pre = at.subtract(const Duration(days: 1));
          if (pre.isAfter(now) && pre.isBefore(horizon)) {
            out.add(
              PlannedNotification(
                'pre-${t.id}',
                pre,
                t.title,
                '$urgentPrefix${tr('Due tomorrow · {company}', {'company': companyName(t)})}',
                t.id,
              ),
            );
          }
        }
      }
    }

    // Morning summary for the next occurrence of the digest time.
    if (s.dailyDigest) {
      var at = DateTime(
        now.year,
        now.month,
        now.day,
        s.digestMinutes ~/ 60,
        s.digestMinutes % 60,
      );
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      final digest = _digestFor(store, at);
      if (digest != null) {
        out.add(PlannedNotification('digest', at, tr('Good morning'), digest));
      }
    }

    // Urgent nudges during working hours (9:00–18:00) today and tomorrow.
    if (s.urgentNudgeHours > 0) {
      final urgent = store.openTasks.where((t) => t.isUrgent).toList();
      if (urgent.isNotEmpty) {
        final body = urgent.length == 1
            ? urgent.first.title
            : tr('{title} and {n} more', {
                'title': urgent.first.title,
                'n': urgent.length - 1,
              });
        var n = 0;
        for (var day = 0; day < 2; day++) {
          for (
            var h = 9 + s.urgentNudgeHours;
            h <= 18;
            h += s.urgentNudgeHours
          ) {
            final at = DateTime(now.year, now.month, now.day + day, h);
            if (at.isAfter(now)) {
              out.add(
                PlannedNotification(
                  'nudge-${n++}',
                  at,
                  urgent.length == 1
                      ? tr('1 urgent task open')
                      : tr('{n} urgent tasks open', {'n': urgent.length}),
                  body,
                ),
              );
            }
          }
        }
      }
    }

    out.sort((a, b) => a.at.compareTo(b.at));
    return out.take(maxPending).toList();
  }

  /// "2 overdue · 1 urgent · 3 due today", projected to [at]; null when there's nothing.
  static String? _digestFor(TaskStore store, DateTime at) {
    var overdue = 0, urgent = 0, today = 0;
    for (final t in store.openTasks) {
      if (t.isOverdue(at)) {
        overdue++;
      } else if (t.isDueOn(at)) {
        today++;
      }
      if (t.isUrgent) urgent++;
    }
    final parts = [
      if (overdue > 0) tr('{n} overdue', {'n': overdue}),
      if (urgent > 0) tr('{n} urgent', {'n': urgent}),
      if (today > 0) tr('{n} due today', {'n': today}),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

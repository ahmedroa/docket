import 'dart:io';

import 'package:docket/core/dates.dart';
import 'package:docket/data/backup.dart';
import 'package:docket/data/models.dart';
import 'package:docket/data/persistence.dart';
import 'package:docket/data/queries.dart';
import 'package:docket/data/settings.dart';
import 'package:docket/data/store.dart';
import 'package:docket/l10n/l10n.dart';
import 'package:docket/services/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wednesday 18 Nov 2026, 11:00.
DateTime clockNow = DateTime(2026, 11, 18, 11);

Future<(TaskStore, MemoryPersistence)> makeStore() async {
  final db = MemoryPersistence();
  final store = TaskStore(db, clock: () => clockNow);
  await store.load();
  return (store, db);
}

Task add(
  TaskStore s,
  String title, {
  Priority priority = Priority.normal,
  int? dueIn,
  int? minutes,
  String? company,
}) {
  final t = s.draftTask(companyId: company)
    ..title = title
    ..priority = priority
    ..dueDate = dueIn == null ? null : addDays(dateOnly(clockNow), dueIn)
    ..dueMinutes = minutes;
  return s.addTask(t);
}

void main() {
  setUp(() {
    clockNow = DateTime(2026, 11, 18, 11);
    L10n.current = AppLanguage.en;
  });

  group('dates', () {
    test('parses typed times', () {
      expect(parseTimeInput('14:30'), 870);
      expect(parseTimeInput('2:30 pm'), 870);
      expect(parseTimeInput('2pm'), 840);
      expect(parseTimeInput('12am'), 0);
      expect(parseTimeInput('12pm'), 720);
      expect(parseTimeInput('1430'), 870);
      expect(parseTimeInput('9'), 540);
      expect(parseTimeInput('25:00'), isNull);
      expect(parseTimeInput('13pm'), isNull);
    });

    test('monthly recurrence clamps to month end', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(addMonths(DateTime(2026, 12, 15), 1), DateTime(2027, 1, 15));
    });

    test('weeks start on Sunday', () {
      expect(startOfWeek(DateTime(2026, 11, 18)), DateTime(2026, 11, 15));
      expect(endOfWeek(DateTime(2026, 11, 18)), DateTime(2026, 11, 21));
    });

    test('relative day labels', () {
      final now = DateTime(2026, 11, 18, 9);
      expect(formatRelativeDay(DateTime(2026, 11, 18), now), 'Today');
      expect(formatRelativeDay(DateTime(2026, 11, 19), now), 'Tomorrow');
      expect(formatRelativeDay(DateTime(2026, 11, 17), now), 'Yesterday');
      expect(formatRelativeDay(DateTime(2026, 11, 21), now), 'Sat');
      expect(formatRelativeDay(DateTime(2027, 1, 2), now), '2 Jan 2027');
    });
  });

  group('store', () {
    test('first launch creates three companies and Personal', () async {
      final (s, db) = await makeStore();
      await s.flush();
      expect(s.companies.map((c) => c.name), [
        'Company A',
        'Company B',
        'Company C',
        'Personal',
      ]);
      expect(db.companies.length, 4);
    });

    test('overdue: date-only at end of day, timed at the minute', () async {
      final (s, _) = await makeStore();
      final dateOnlyToday = add(s, 'a', dueIn: 0);
      final timedPast = add(s, 'b', dueIn: 0, minutes: 10 * 60);
      final timedFuture = add(s, 'c', dueIn: 0, minutes: 12 * 60);
      final yesterday = add(s, 'd', dueIn: -1);
      expect(dateOnlyToday.isOverdue(clockNow), isFalse);
      expect(timedPast.isOverdue(clockNow), isTrue);
      expect(timedFuture.isOverdue(clockNow), isFalse);
      expect(yesterday.isOverdue(clockNow), isTrue);
      s.setStatus(yesterday, TaskStatus.done);
      expect(yesterday.isOverdue(clockNow), isFalse);
    });

    test('Today ordering: urgent, overdue, due soon, then the rest', () async {
      final (s, _) = await makeStore();
      add(s, 'normal-today', dueIn: 0);
      add(s, 'low-today', priority: Priority.low, dueIn: 0);
      add(s, 'timed-later', dueIn: 0, minutes: 17 * 60);
      add(s, 'timed-soon', dueIn: 0, minutes: 12 * 60);
      add(s, 'overdue', dueIn: -3);
      add(s, 'urgent-no-date', priority: Priority.urgent);
      add(s, 'tomorrow', dueIn: 1);
      add(s, 'no-date');
      expect(s.todayTasks().map((t) => t.title), [
        'urgent-no-date',
        'overdue',
        'timed-soon',
        'timed-later',
        'normal-today',
        'low-today',
      ]);
    });

    test(
      'completed tasks stay at the bottom of the lists they belonged to',
      () async {
        final (s, _) = await makeStore();
        final a = s.companies[0].id;
        final b = s.companies[1].id;
        final plain = add(s, 'plain', company: a);
        final urgent = add(s, 'urgent', priority: Priority.urgent, company: a);
        final late = add(s, 'late', dueIn: -2, company: a);
        final started = add(s, 'started', company: a);
        final yesterday = add(s, 'yesterday', company: a);
        final other = add(s, 'other company', company: b);
        s.setStatus(started, TaskStatus.inProgress);

        clockNow = DateTime(2026, 11, 17, 16);
        s.setStatus(yesterday, TaskStatus.done);
        clockNow = DateTime(2026, 11, 18, 11);
        for (final t in [plain, urgent, late, started, other]) {
          clockNow = clockNow.add(const Duration(minutes: 1));
          s.setStatus(t, TaskStatus.done);
        }

        List<String> titles(List<Task> l) => l.map((t) => t.title).toList();
        // Newest first; the action lists keep only what was finished today.
        expect(titles(s.completedFor(ListKind.today)), [
          'other company',
          'started',
          'late',
          'urgent',
          'plain',
        ]);
        expect(titles(s.completedFor(ListKind.urgent)), ['urgent']);
        expect(titles(s.completedFor(ListKind.overdue)), ['late']);
        expect(titles(s.completedFor(ListKind.inProgress)), ['started']);
        expect(titles(s.completedFor(ListKind.all)).last, 'yesterday');
        expect(s.completedFor(ListKind.completed), isEmpty);
        expect(titles(s.completedForCompany(a)), [
          'started',
          'late',
          'urgent',
          'plain',
          'yesterday',
        ]);
        expect(titles(s.completedForCompany(a, startedOnly: true)), [
          'started',
        ]);
        // The open lists themselves never mix them in.
        expect(s.listTasks(ListKind.all, sort: SortMode.manual), isEmpty);
        expect(s.todayTasks(), isEmpty);
      },
    );

    test('keeping completed tasks in lists is on by default and saved', () {
      expect(AppSettings().showCompletedInLists, isTrue);
      expect(AppSettings.fromJson({}).showCompletedInLists, isTrue);
      final off = AppSettings()..showCompletedInLists = false;
      expect(AppSettings.fromJson(off.toJson()).showCompletedInLists, isFalse);
    });

    test(
      'completing a recurring task schedules the next one, catching up if late',
      () async {
        final (s, _) = await makeStore();
        final t = add(s, 'standup', dueIn: -10)..recurrence = Recurrence.weekly;
        final change = s.setStatus(t, TaskStatus.done)!;
        final next = change.spawned!;
        expect(next.status, TaskStatus.todo);
        expect(
          daysBetween(clockNow, next.dueDate!) >= 0,
          isTrue,
          reason: 'not already overdue',
        );
        expect(next.dueDate, DateTime(2026, 11, 22)); // 8 Nov + 7 + 7
        s.undoStatus(change);
        expect(t.status, TaskStatus.todo);
        expect(s.task(next.id), isNull);
      },
    );

    test('undo restores previous status and timestamps', () async {
      final (s, _) = await makeStore();
      final t = add(s, 'x');
      final c1 = s.setStatus(t, TaskStatus.inProgress)!;
      expect(t.startedAt, isNotNull);
      s.undoStatus(c1);
      expect(t.status, TaskStatus.todo);
      expect(t.startedAt, isNull);
    });

    test(
      'manual reorder places the task exactly and survives renumbering',
      () async {
        final (s, _) = await makeStore();
        final c = s.companies.first.id;
        for (final n in ['a', 'b', 'c', 'd']) {
          add(s, n, company: c);
        }
        List<String> order() => s
            .tasksForCompany(c, TaskStatus.todo, SortMode.manual)
            .map((t) => t.title)
            .toList();
        expect(order(), ['d', 'c', 'b', 'a']); // newest on top
        s.reorder(s.tasksForCompany(c, TaskStatus.todo, SortMode.manual), 3, 0);
        expect(order(), ['a', 'd', 'c', 'b']);
        s.reorder(s.tasksForCompany(c, TaskStatus.todo, SortMode.manual), 0, 3);
        expect(order(), ['d', 'c', 'b', 'a']);
        s.reorder(s.tasksForCompany(c, TaskStatus.todo, SortMode.manual), 1, 2);
        expect(order(), ['d', 'b', 'c', 'a']);
      },
    );

    test('timer accumulates and only one runs at a time', () async {
      final (s, _) = await makeStore();
      final a = add(s, 'a');
      final b = add(s, 'b');
      s.startTimer(a);
      expect(a.status, TaskStatus.inProgress);
      clockNow = clockNow.add(const Duration(minutes: 25));
      s.startTimer(b);
      expect(a.isTimerRunning, isFalse);
      expect(a.timeSpentSeconds, 25 * 60);
      clockNow = clockNow.add(const Duration(minutes: 5));
      s.setStatus(b, TaskStatus.done);
      expect(b.timeSpentSeconds, 5 * 60);
      expect(b.isTimerRunning, isFalse);
    });

    test('every mutation reaches persistence', () async {
      final (s, db) = await makeStore();
      final t = add(s, 'persist me', dueIn: 2, minutes: 9 * 60);
      s.addSubtask(t, 'sub');
      s.addUpdate(t, 'progress');
      s.setPriority(t, Priority.urgent);
      await s.flush();
      final reloaded = TaskStore(db, clock: () => clockNow);
      await reloaded.load();
      final r = reloaded.task(t.id)!;
      expect(r.title, 'persist me');
      expect(r.priority, Priority.urgent);
      expect(r.dueMinutes, 540);
      expect(r.liveSubtasks.single.title, 'sub');
      expect(r.liveUpdates.single.body, 'progress');
    });

    test('quick add syntax', () {
      final q = parseQuickInput('Call the bank #finance !');
      expect(q.title, 'Call the bank');
      expect(q.priority, Priority.urgent);
      expect(q.tags, ['finance']);
      expect(parseQuickInput('Ship it!!').priority, Priority.urgent);
      expect(parseQuickInput('Ship it!!').title, 'Ship it');
      expect(parseQuickInput('Wow!').title, 'Wow!');
      expect(parseQuickInput('later !low').priority, Priority.low);
    });
  });

  group('search', () {
    test(
      'matches company, priority, status, dates and folds Arabic letters',
      () async {
        final (s, _) = await makeStore();
        final pers = s.personal;
        add(s, 'أرسل الفاتورة', company: pers.id, dueIn: 1);
        add(s, 'Board deck', priority: Priority.urgent, dueIn: 0);
        final f = TaskFilter();
        expect(s.search('ارسل', f).single.title, 'أرسل الفاتورة');
        expect(s.search('personal tomorrow', f).single.title, 'أرسل الفاتورة');
        expect(s.search('urgent', f).single.title, 'Board deck');
        expect(s.search('company a today', f).single.title, 'Board deck');
        f.urgent = true;
        expect(s.search('', f).single.title, 'Board deck');
      },
    );

    test('this week filter uses Sunday–Saturday', () async {
      final (s, _) = await makeStore();
      add(s, 'sat', dueIn: 3); // Sat 21
      add(s, 'sun', dueIn: 4); // Sun 22 → next week
      final f = TaskFilter()..thisWeek = true;
      expect(s.search('', f).map((t) => t.title), ['sat']);
    });
  });

  group('reminders', () {
    test('plans due, early and morning notifications', () async {
      final (s, _) = await makeStore();
      s.settings
        ..remindBefore = 30
        ..digestMinutes = 9 * 60;
      add(s, 'timed', dueIn: 0, minutes: 14 * 60);
      add(s, 'date-only', dueIn: 1);
      add(s, 'old', dueIn: -2);
      final plan = ReminderService.plan(s, clockNow);
      final ids = plan.map((p) => p.id.split('-').first).toList();
      expect(plan.first.at, DateTime(2026, 11, 18, 13, 30)); // 30 min before
      expect(ids.where((i) => i == 'due').length, 2);
      final digest = plan.firstWhere((p) => p.id == 'digest');
      expect(digest.at, DateTime(2026, 11, 19, 9));
      // By tomorrow 9:00: "old" and "timed" are overdue, "date-only" is due.
      expect(digest.body, '2 overdue · 1 due today');
    });

    test('nothing is planned in the past and nothing for done tasks', () async {
      final (s, _) = await makeStore();
      final t = add(s, 'x', dueIn: 0, minutes: 10 * 60);
      expect(
        ReminderService.plan(s, clockNow).where((p) => p.taskId == t.id),
        isEmpty,
      );
      final u = add(s, 'y', dueIn: 1, minutes: 10 * 60);
      s.setStatus(u, TaskStatus.done);
      expect(
        ReminderService.plan(s, clockNow).where((p) => p.taskId == u.id),
        isEmpty,
      );
    });
  });

  group('session list', () {
    test('add, tick, rename, delete — apart from company tasks', () async {
      final (s, db) = await makeStore();
      expect(s.settings.sessionStartedAt, isNull);
      final a = s.addSessionItem('  Reply to emails ')!;
      expect(a.title, 'Reply to emails');
      expect(s.settings.sessionStartedAt, clockNow, reason: 'starts here');
      clockNow = clockNow.add(const Duration(minutes: 5));
      final b = s.addSessionItem('Fix the build')!;
      final c = s.addSessionItem('Call Sara')!;
      expect(s.addSessionItem('   '), isNull);
      List<String> titles() => s.sessionItems.map((i) => i.title).toList();
      expect(titles(), ['Reply to emails', 'Fix the build', 'Call Sara']);

      // Ticked items drop to the bottom, newest first; unticking returns them.
      clockNow = clockNow.add(const Duration(minutes: 1));
      s.toggleSessionItem(a);
      clockNow = clockNow.add(const Duration(minutes: 1));
      s.toggleSessionItem(c);
      expect(titles(), ['Fix the build', 'Call Sara', 'Reply to emails']);
      expect(c.done && c.doneAt == clockNow, isTrue);
      s.toggleSessionItem(c);
      expect(c.doneAt, isNull);
      expect(titles(), ['Fix the build', 'Call Sara', 'Reply to emails']);

      s.renameSessionItem(b, 'Fix the CI build');
      s.renameSessionItem(b, '  ');
      expect(b.title, 'Fix the CI build');
      s.deleteSessionItem(c);
      expect(titles(), ['Fix the CI build', 'Reply to emails']);
      s.restoreSessionItems([c]);
      expect(titles(), ['Fix the CI build', 'Call Sara', 'Reply to emails']);

      // Never mixed into tasks, counts or lists.
      expect(s.allTasks, isEmpty);
      expect(s.summary().open, 0);

      // Survives a reload from storage.
      await s.flush();
      expect(db.sessionItems.length, 3);
      final reloaded = TaskStore(db, clock: () => clockNow);
      await reloaded.load();
      expect(reloaded.sessionItems.map((i) => i.title), titles());
      expect(reloaded.sessionItems.last.done, isTrue);
    });

    test('clear completed and new session, both undoable', () async {
      final (s, _) = await makeStore();
      final a = s.addSessionItem('a')!;
      s.addSessionItem('b');
      s.toggleSessionItem(a);
      final started = s.settings.sessionStartedAt;

      final cleared = s.clearCompletedSession();
      expect(cleared, [a]);
      expect(s.sessionItems.map((i) => i.title), ['b']);
      s.restoreSessionItems(cleared);
      expect(s.sessionItems.length, 2);

      final (items, was) = s.startNewSession();
      expect(s.sessionItems, isEmpty);
      expect(s.settings.sessionStartedAt, isNull);
      s.restoreSessionItems(items, startedAt: was);
      expect(s.sessionItems.length, 2);
      expect(s.settings.sessionStartedAt, started);

      // After a new session the first line written starts the clock again.
      s.startNewSession();
      clockNow = clockNow.add(const Duration(hours: 2));
      s.addSessionItem('fresh');
      expect(s.settings.sessionStartedAt, clockNow);
    });

    test('session items travel with backups', () async {
      final (s, _) = await makeStore();
      s.addSessionItem('Keep me in the backup');
      final json = BackupService(s, Directory.systemTemp).encode();
      final (fresh, _) = await makeStore();
      final (snapshot, _) = BackupService.decode(json);
      await fresh.merge(snapshot);
      expect(fresh.sessionItems.single.title, 'Keep me in the backup');
      expect(fresh.allTasks, isEmpty);
    });
  });

  group('backup', () {
    test('export → import into an empty store restores everything', () async {
      final (s, _) = await makeStore();
      final t = add(s, 'Keep me', dueIn: 3, minutes: 600)..tags = ['a'];
      s.addSubtask(t, 'sub');
      s.addUpdate(t, 'note');
      final dir = await Directory.systemTemp.createTemp('docket-test');
      final backups = BackupService(s, dir);
      final json = backups.encode();

      final (fresh, _) = await makeStore();
      final (snapshot, _) = BackupService.decode(json);
      final result = await fresh.merge(snapshot);
      expect(result.added, greaterThan(0));
      final r = fresh.task(t.id)!;
      expect(r.title, 'Keep me');
      expect(r.liveSubtasks.single.title, 'sub');
      expect(r.liveUpdates.single.body, 'note');
      await dir.delete(recursive: true);
    });

    test('merge keeps the newer copy', () async {
      final (s, _) = await makeStore();
      final t = add(s, 'old title');
      final (snapshot, _) = BackupService.decode(
        BackupService(s, Directory.systemTemp).encode(),
      );
      clockNow = clockNow.add(const Duration(minutes: 1));
      s.updateTask(t, (t) => t.title = 'new title');
      await s.merge(snapshot);
      expect(s.task(t.id)!.title, 'new title');
    });

    test('rejects files that are not Docket backups', () {
      expect(
        () => BackupService.decode('{"hello": 1}'),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => BackupService.decode('not json'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('auto backup rotates', () async {
      final (s, _) = await makeStore();
      add(s, 'x');
      s.settings.backupKeep = 2;
      final dir = await Directory.systemTemp.createTemp('docket-rot');
      final b = BackupService(s, dir);
      for (var i = 0; i < 4; i++) {
        clockNow = clockNow.add(const Duration(days: 1));
        expect(await b.autoBackupIfDue(), isNotNull);
      }
      expect(await b.autoBackupIfDue(), isNull, reason: 'once a day');
      expect((await b.list()).length, 2);
      await dir.delete(recursive: true);
    });
  });
}

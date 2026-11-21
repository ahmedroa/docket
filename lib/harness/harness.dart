import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../app.dart';
import '../core/dates.dart';
import '../data/models.dart';
import '../data/queries.dart';
import '../data/settings.dart';
import '../data/store.dart';
import '../l10n/l10n.dart';
import '../ui/controller.dart';
import '../ui/pages/company_edit_page.dart';
import '../ui/pages/search_page.dart';
import '../ui/pages/task_editor_page.dart';
import 'demo.dart';

/// Development harness, enabled with the DOCKET_HARNESS environment variable.
///
/// * `snapshot`  — seeds demo data in a scratch database and renders every
///                 screen (light + dark) to PNG files.
/// * `selftest1` — drives the store against the real SQLite plugin and records
///                 what it expects to find.
/// * `selftest2` — a fresh process that reloads the database and checks that
///                 everything from `selftest1` survived the restart.
Future<void> runHarness(String mode, AppController app, Directory dir) async {
  // `activation` is measured natively; Dart just stays out of the way.
  if (mode == 'activation') return;
  try {
    switch (mode) {
      case 'snapshot':
        await _snapshot(app, Directory('${dir.path}/shots'));
      case 'selftest1':
        await _selfTestWrite(app, dir);
      case 'selftest2':
        await _selfTestVerify(app, dir);
      case 'demoshots':
        await _demoShots(app, Directory('${dir.path}/shots'));
    }
  } catch (e, st) {
    await File('${dir.path}/harness-error.txt').writeAsString('$e\n$st');
  }
  await app.store.flush();
  await app.store.flushSettings();
  exit(0);
}

// ---------------------------------------------------------------------------
// Screenshots
// ---------------------------------------------------------------------------

Future<void> _settle([int ms = 500]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  try {
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 2),
    );
  } catch (_) {}
}

Future<void> _capture(Directory out, String name) async {
  await _settle(550);
  // ignore: avoid_print
  print(
    'HARNESS $name frame=${SchedulerBinding.instance.currentSystemFrameTimeStamp} '
    'scheduled=${SchedulerBinding.instance.hasScheduledFrame}',
  );
  final boundary =
      DocketApp.captureKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('${out.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
}

Future<void> _snapshot(AppController app, Directory out) async {
  await out.create(recursive: true);
  await _settle(1500);
  final ids = seedDemo(app.store);
  final store = app.store;
  final atlas = store.companies.first;

  // Arabic in both themes, then English (light) for comparison.
  for (final (lang, mode) in [
    (AppLanguage.ar, ThemeMode.light),
    (AppLanguage.ar, ThemeMode.dark),
    (AppLanguage.en, ThemeMode.light),
  ]) {
    final suffix = '${lang.code}-${mode == ThemeMode.light ? 'light' : 'dark'}';
    app.setLanguage(lang);
    store.updateSettings((s) => s.themeMode = mode);
    await _settle(600);

    app.goHome();
    await _capture(out, '01-home-$suffix');

    app.openCompany(atlas);
    await _capture(out, '02-company-todo-$suffix');

    app.goHome();
    app.openCompany(atlas, tab: TaskStatus.inProgress);
    await _capture(out, '03-company-progress-$suffix');

    app.goHome();
    app.openCompany(atlas, tab: TaskStatus.done);
    await _capture(out, '04-company-done-$suffix');

    app.goHome();
    app.openTask(store.task(ids['brand'])!);
    await _capture(out, '05-editor-$suffix');

    app.goHome();
    app.push('newTask', const TaskEditorPage.create());
    await _capture(out, '06-new-task-$suffix');

    app.goHome();
    app.openQuickAdd();
    await _capture(out, '07-quick-add-$suffix');

    app.goHome();
    app.push('search', const SearchPage(initialQuery: 'review'));
    await _capture(out, '08-search-$suffix');

    app.openList(ListKind.today);
    await _capture(out, '09-today-$suffix');

    app.openList(ListKind.all);
    await _capture(out, '10-all-$suffix');

    app.openList(ListKind.completed);
    await _capture(out, '11-completed-$suffix');

    app.openSettings();
    await _capture(out, '12-settings-$suffix');

    app.goHome();
    app.push('companyEdit', CompanyEditPage(companyId: atlas.id));
    await _capture(out, '13-company-edit-$suffix');

    app.goHome();
  }
  // Small and Large drop-downs.
  app.setLanguage(AppLanguage.ar);
  store.updateSettings((s) => s.themeMode = ThemeMode.light);
  for (final mode in [DisplayMode.small, DisplayMode.large]) {
    app.setDisplayMode(mode);
    await _settle(900);
    app.goHome();
    await _capture(out, '20-home-${mode.key}-ar-light');
  }

  // Curtain: a stand-in desktop is painted behind the glass for the picture.
  CurtainBackdrop.debugPaint = true;
  app.setDisplayMode(DisplayMode.curtain);
  await _settle(1200);
  for (final (lang, mode) in [
    (AppLanguage.ar, ThemeMode.light),
    (AppLanguage.ar, ThemeMode.dark),
    (AppLanguage.en, ThemeMode.light),
  ]) {
    final suffix = '${lang.code}-${mode == ThemeMode.light ? 'light' : 'dark'}';
    app.setLanguage(lang);
    store.updateSettings((s) => s.themeMode = mode);
    app.applyDisplayMode();
    await _settle(600);
    app.goHome();
    await _capture(out, '30-curtain-overview-$suffix');
    if (lang == AppLanguage.ar && mode == ThemeMode.light) {
      app.openCompany(atlas);
      app.openTask(store.task(ids['brand'])!);
      await _capture(out, '31-curtain-board-pane-$suffix');
      app.curtain.closeTask();
      app.openList(ListKind.today);
      await _capture(out, '32-curtain-today-$suffix');
      app.goHome();
      app.curtain.searchController.text = 'review';
      app.curtain.setQuery('review');
      await _capture(out, '33-curtain-search-$suffix');
      app.goHome();
      app.openSettings();
      await _capture(out, '34-curtain-settings-$suffix');
      app.goHome();
    }
  }
  CurtainBackdrop.debugPaint = false;
  app.setDisplayMode(DisplayMode.normal);
  store.updateSettings((s) => s.themeMode = ThemeMode.system);
}

/// The demo-mode data as it will be photographed: curtain and drop-down,
/// Arabic and English interface.
Future<void> _demoShots(AppController app, Directory out) async {
  await out.create(recursive: true);
  await _settle(1500);
  final store = app.store;
  store.localizeNames = false;
  store.updateSettings((s) => s.welcomeDismissed = true);
  app.setUseProjects(true);
  seedShowcase(store);
  app.setLanguage(AppLanguage.ar);
  store.updateSettings((s) => s.themeMode = ThemeMode.light);
  CurtainBackdrop.debugPaint = true;
  app.setDisplayMode(DisplayMode.curtain);
  await _settle(1200);
  for (final lang in AppLanguage.values) {
    app.setLanguage(lang);
    app.applyDisplayMode();
    await _settle(600);
    app.goHome();
    await _capture(out, '40-demo-curtain-${lang.code}');
  }
  CurtainBackdrop.debugPaint = false;
  app.setLanguage(AppLanguage.ar);
  app.setDisplayMode(DisplayMode.normal);
  await _settle(900);
  app.goHome();
  await _capture(out, '41-demo-home-ar');
}

/// Realistic sample data (fictional companies, English + Arabic titles).
Map<String, String> seedDemo(TaskStore store) {
  final now = store.now;
  final today = dateOnly(now);
  final cs = store.companies;
  store.updateCompany(cs[0], name: 'Atlas Studio', icon: 'design');
  store.updateCompany(cs[1], name: 'Nimbus Labs', icon: 'code');
  store.updateCompany(cs[2], name: 'Harbor & Co.', icon: 'storefront');
  store.updateSettings((s) => s.welcomeDismissed = true);
  final atlas = cs[0].id,
      nimbus = cs[1].id,
      harbor = cs[2].id,
      personal = cs[3].id;
  final ids = <String, String>{};

  Task add(
    String company,
    String title, {
    String description = '',
    Priority priority = Priority.normal,
    TaskStatus status = TaskStatus.todo,
    int? dueIn,
    int? minutes,
    List<String> tags = const [],
    List<String> subtasks = const [],
    int doneSubtasks = 0,
    Recurrence recurrence = Recurrence.none,
    String? key,
  }) {
    final t = store.draftTask(companyId: company)
      ..title = title
      ..description = description
      ..priority = priority
      ..tags = List.of(tags)
      ..recurrence = recurrence
      ..dueDate = dueIn == null ? null : addDays(today, dueIn)
      ..dueMinutes = minutes;
    final saved = store.addTask(t, subtasks: subtasks);
    for (final s in saved.liveSubtasks.take(doneSubtasks)) {
      store.toggleSubtask(saved, s);
    }
    if (status != TaskStatus.todo) store.setStatus(saved, status);
    if (key != null) ids[key] = saved.id;
    return saved;
  }

  // Completed history first so it sits below.
  add(atlas, 'Kickoff call with client', status: TaskStatus.done);
  add(
    atlas,
    'Moodboard for spring campaign',
    status: TaskStatus.done,
    tags: ['design'],
  );
  add(nimbus, 'Migrate CI to new runners', status: TaskStatus.done);
  add(nimbus, 'Release 3.2.0 to TestFlight', status: TaskStatus.done);
  add(harbor, 'Quarterly stock count', status: TaskStatus.done);
  add(personal, 'Book dentist appointment', status: TaskStatus.done);

  add(
    atlas,
    'Send invoice #1042',
    priority: Priority.low,
    dueIn: 5,
    tags: ['finance'],
  );
  add(
    atlas,
    'Prepare Q4 board deck',
    description: 'Revenue, pipeline and hiring slides',
    dueIn: 1,
    tags: ['finance'],
    subtasks: ['Pull revenue numbers', 'Pipeline slide', 'Hiring plan'],
    doneSubtasks: 1,
  );
  add(
    atlas,
    'مراجعة عقد المورد الجديد',
    description: 'التأكد من بنود الدفع ومدة العقد',
    priority: Priority.urgent,
    dueIn: -2,
  );
  final brand = add(
    atlas,
    'Finalize brand guidelines v2',
    description: 'Typography and colour tokens for the client handoff',
    priority: Priority.urgent,
    status: TaskStatus.inProgress,
    dueIn: 0,
    minutes: 14 * 60,
    tags: ['design', 'client'],
    subtasks: [
      'Type scale',
      'Colour tokens',
      'Logo spacing',
      'Export Figma library',
      'Send to client',
    ],
    doneSubtasks: 3,
    key: 'brand',
  );
  store.updateTask(brand, (t) {
    t.timeSpentSeconds = 80 * 60;
    t.expectedDate = addDays(today, 1);
    t.notes =
        'Client prefers the warmer palette. Keep accessibility contrast ≥ 4.5.';
  });
  store.addUpdate(brand, 'Shared type scale draft with Sara for feedback');
  store.addUpdate(brand, 'Colour tokens approved');

  add(
    nimbus,
    'Fix login crash on iOS 18',
    priority: Priority.urgent,
    status: TaskStatus.inProgress,
    dueIn: 0,
    tags: ['bug'],
  );
  add(nimbus, 'Code review: payments module', dueIn: 0, minutes: 16 * 60 + 30);
  add(
    nimbus,
    'Write API docs for v3',
    description: 'Endpoints, auth, rate limits',
    priority: Priority.low,
  );
  add(
    nimbus,
    'Sprint planning',
    dueIn: 2,
    minutes: 10 * 60,
    recurrence: Recurrence.weekly,
  );

  add(harbor, 'تحديث قائمة الأسعار', dueIn: 3, tags: ['pricing']);
  add(harbor, 'Supplier follow-up', dueIn: -1, minutes: 11 * 60);
  add(harbor, 'Weekly sales report', dueIn: 4, recurrence: Recurrence.weekly);

  add(personal, 'اتصل بالوالدة', dueIn: 0, minutes: 19 * 60);
  add(personal, 'Renew passport', priority: Priority.low, dueIn: 12);
  add(
    personal,
    'Gym',
    dueIn: 0,
    minutes: 20 * 60,
    recurrence: Recurrence.daily,
  );
  // A session list under way: one being worked on, one left, two done.
  final first = store.addSessionItem('الرد على إيميلات العملاء')!;
  final working = store.addSessionItem('Review PR #214 before standup')!;
  store.addSessionItem('مراجعة عرض الربع الرابع مع الفريق');
  final last = store.addSessionItem('Book the venue for Thursday')!;
  for (final i in [first, first, working, last, last]) {
    store.advanceSessionItem(i);
  }
  store.updateSettings(
    (s) => s.sessionStartedAt = now.subtract(const Duration(minutes: 50)),
  );
  return ids;
}

// ---------------------------------------------------------------------------
// Persistence self-test (two processes)
// ---------------------------------------------------------------------------

Map<String, Object?> _fingerprint(TaskStore store) {
  final tasks = store.snapshot().tasks.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return {
    'companies': [
      for (final c in store.companies)
        {'id': c.id, 'name': c.name, 'color': c.color, 'icon': c.icon},
    ],
    'tasks': [
      for (final t in tasks)
        {
          'id': t.id,
          'company': t.companyId,
          'title': t.title,
          'description': t.description,
          'notes': t.notes,
          'status': t.status.key,
          'priority': t.priority.key,
          'due': t.dueDate == null ? null : ymd(t.dueDate!),
          'dueMinutes': t.dueMinutes,
          'expected': t.expectedDate == null ? null : ymd(t.expectedDate!),
          'tags': t.tags,
          'sort': t.sortOrder,
          'recurrence': t.recurrence.key,
          'time': t.timeSpentSeconds,
          'timerRunning': t.isTimerRunning,
          'archived': t.isArchived,
          'deleted': t.isDeleted,
          'completed': t.completedAt?.millisecondsSinceEpoch,
          'subtasks': [for (final s in t.liveSubtasks) '${s.title}:${s.done}'],
          'updates': [for (final u in t.liveUpdates) u.body],
        },
    ],
    'session': [
      for (final i in store.sessionItems)
        '${i.title}:${i.status.key}:${i.sortOrder}',
    ],
    'settings': {
      'sessionStartedAt':
          store.settings.sessionStartedAt?.millisecondsSinceEpoch,
      'themeMode': store.settings.themeMode.name,
      'use24h': store.settings.use24h,
      'sortMode': store.settings.sortMode.key,
      'toggleHotKey': store.settings.toggleHotKey.label,
    },
  };
}

Future<void> _selfTestWrite(AppController app, Directory dir) async {
  final store = app.store;
  final log = <String>[];
  void check(bool ok, String what) => log.add('${ok ? 'PASS' : 'FAIL'}  $what');

  final cs = store.companies;
  check(
    cs.length == 4 && cs.where((c) => c.isPersonal).length == 1,
    'seeds 3 companies + Personal',
  );

  final today = dateOnly(store.now);
  final a = store.addTask(
    store.draftTask(companyId: cs[0].id)
      ..title = 'Alpha'
      ..priority = Priority.urgent
      ..dueDate = today
      ..dueMinutes = 10 * 60
      ..tags = ['x', 'y'],
  );
  final b = store.addTask(
    store.draftTask(companyId: cs[0].id)
      ..title = 'Bravo weekly'
      ..recurrence = Recurrence.weekly
      ..dueDate = today,
    subtasks: ['one', 'two'],
  );
  final c = store.quickAdd('Charlie #ops !', companyId: cs[1].id);
  check(
    c.priority == Priority.urgent &&
        c.tags.contains('ops') &&
        c.title == 'Charlie',
    'quick add parses ! and #tag',
  );
  final d = store.quickAdd('مهمة دلتا', companyId: cs[3].id);
  final e = store.quickAdd('Echo', companyId: cs[2].id);

  store.setStatus(a, TaskStatus.inProgress);
  store.startTimer(a);
  store.addUpdate(a, 'Started on alpha');
  store.updateTask(a, (t) {
    t.expectedDate = addDays(today, 2);
    t.description = 'Line one\nسطر عربي';
    t.notes = 'note';
  });
  check(a.startedAt != null && a.isTimerRunning, 'start + timer');

  final change = store.setStatus(b, TaskStatus.done);
  final spawned = change?.spawned;
  check(
    spawned != null &&
        spawned.dueDate != null &&
        daysBetween(today, spawned.dueDate!) == 7,
    'recurring weekly spawns next +7d',
  );
  check(
    spawned != null &&
        spawned.liveSubtasks.length == 2 &&
        spawned.liveSubtasks.every((s) => !s.done),
    'spawned copy has fresh subtasks',
  );

  store.delete(d);
  check(store.task(d.id) == null, 'delete hides task');
  store.restore(d);
  check(store.task(d.id) != null, 'restore brings it back');

  store.setArchived(e, true);
  check(
    store.activeTasks.every((t) => t.id != e.id),
    'archived task hidden from active',
  );

  final dup = store.duplicate(a);
  check(
    dup.title == a.title && dup.liveSubtasks.length == a.liveSubtasks.length,
    'duplicate',
  );

  final todo = store.tasksForCompany(
    cs[0].id,
    TaskStatus.inProgress,
    store.settings.sortMode,
  );
  if (todo.length >= 2) {
    final last = todo.last;
    store.reorder(todo, todo.length - 1, 0);
    final after = store.tasksForCompany(
      cs[0].id,
      TaskStatus.inProgress,
      store.settings.sortMode,
    );
    check(after.first.id == last.id, 'drag reorder moves task to top');
  }

  store.updateCompany(
    cs[0],
    name: 'Renamed Co',
    color: 0xFFE64980,
    icon: 'bolt',
  );
  final temp = store.addCompany(
    name: 'Temp Co',
    color: 0xFF868E96,
    icon: 'globe',
  );
  final moved = store.quickAdd('Foxtrot', companyId: temp.id);
  store.deleteCompany(temp, moveTasksTo: store.personal.id);
  check(
    store.task(moved.id)?.companyId == store.personal.id,
    'deleting company moves tasks to Personal',
  );

  // Session list: its own table, apart from tasks.
  final tasksBefore = store.allTasks.length;
  final s1 = store.addSessionItem('رد على الإيميلات')!;
  store.addSessionItem('Review PR #12');
  final s3 = store.addSessionItem('Gone soon')!;
  store.advanceSessionItem(s1); // working on it
  store.advanceSessionItem(s1); // done
  store.renameSessionItem(s3, 'Renamed item');
  store.advanceSessionItem(s3); // working on it: listed first
  final s4 = store.addSessionItem('Deleted item')!;
  store.deleteSessionItem(s4);
  check(
    store.sessionItems.map((i) => i.title).join('|') ==
            'Renamed item|Review PR #12|رد على الإيميلات' &&
        store.allTasks.length == tasksBefore &&
        store.settings.sessionStartedAt != null,
    'session items: own list, done at the bottom, tasks untouched',
  );

  store.updateSettings((s) {
    s.themeMode = ThemeMode.dark;
    s.use24h = true;
  });

  // Export → import round trip (merge should find nothing new).
  final exportPath = '${dir.path}/export.json';
  await app.backups.exportTo(exportPath);
  final r = await app.backups.importFrom(exportPath);
  check(r.added == 0 && r.updated == 0, 'import of own export changes nothing');

  await store.flush();
  await store.flushSettings();
  await File('${dir.path}/expected.json')
      .writeAsString(jsonEncode(_fingerprint(store)));
  await File('${dir.path}/selftest1.txt').writeAsString(log.join('\n'));
}

Future<void> _selfTestVerify(AppController app, Directory dir) async {
  final store = app.store;
  final log = <String>[];
  final expected = await File('${dir.path}/expected.json').readAsString();
  final actual = jsonEncode(_fingerprint(store));
  if (expected == actual) {
    log.add(
      'PASS  every task, subtask, update, session item, company and setting survived a restart',
    );
  } else {
    log.add('FAIL  data differs after restart');
    log.add('expected: $expected');
    log.add('actual:   $actual');
  }
  final running = store.runningTimer;
  log.add(
    '${running != null ? 'PASS' : 'FAIL'}  running timer survives restart',
  );
  await File('${dir.path}/selftest2.txt').writeAsString(log.join('\n'));
}

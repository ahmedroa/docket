import 'dart:io';

import 'package:docket/app.dart';
import 'package:docket/data/backup.dart';
import 'package:docket/data/models.dart';
import 'package:docket/data/persistence.dart';
import 'package:docket/data/settings.dart';
import 'package:docket/data/store.dart';
import 'package:docket/l10n/l10n.dart';
import 'package:docket/services/hotkeys.dart';
import 'package:docket/services/reminders.dart';
import 'package:docket/ui/controller.dart';
import 'package:docket/ui/pages/curtain_page.dart';
import 'package:docket/ui/pages/task_editor_page.dart';
import 'package:docket/ui/widgets/session_list.dart';
import 'package:docket/ui/widgets/task_row.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real UI against an in-memory store, as a user would.
void main() {
  late List<String> nativeCalls;

  setUp(() {
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('docket/native'), (
          call,
        ) async {
          nativeCalls.add(call.method);
          return null;
        });
  });

  Future<AppController> pumpApp(
    WidgetTester tester, {
    AppLanguage language = AppLanguage.en,
    DisplayMode mode = DisplayMode.normal,
    Size size = const Size(400, 640),
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    L10n.current = language;
    await tester.binding.setSurfaceSize(size);
    // What layout sees (MediaQuery) comes from the view, not the surface.
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = TaskStore(MemoryPersistence());
    await tester.runAsync(store.load);
    final app = AppController(
      store: store,
      backups: BackupService(store, Directory.systemTemp),
      reminders: ReminderService(store),
      hotkeys: HotKeyService(store),
    );
    store.updateSettings((s) {
      s.welcomeDismissed = true;
      s.language = language;
      s.displayMode = mode;
    });
    store.localizeDefaultNames(language);
    await tester.pumpWidget(DocketApp(app: app));
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> cmd(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    // Let toast timers expire.
    await tester.pump(const Duration(seconds: 6));
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('quick add bar → complete from Today → undo', (tester) async {
    final app = await pumpApp(tester);
    final store = app.store;

    await tester.enterText(
      find.byType(TextField).last,
      'Call the bank #finance !',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final task = store.allTasks.single;
    expect(task.title, 'Call the bank');
    expect(task.priority, Priority.urgent);
    expect(task.tags, ['finance']);
    expect(find.text('Added to Personal'), findsOneWidget);

    // Urgent tasks without a date show under Today. The circle moves one
    // step per click: first it starts the task, then it completes it.
    expect(find.text('Call the bank'), findsOneWidget);
    await tester.tap(find.byType(StatusCircle).first);
    await tester.pumpAndSettle();
    expect(task.status, TaskStatus.inProgress);
    expect(find.text('Moved to In Progress'), findsOneWidget);
    await tester.tap(find.byType(StatusCircle).first);
    await tester.pumpAndSettle();
    expect(task.status, TaskStatus.done);
    expect(find.text('Task completed'), findsOneWidget);
    expect(
      find.text('Call the bank'),
      findsOneWidget,
      reason: 'a completed task stays in Today, crossed out',
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(task.status, TaskStatus.inProgress, reason: 'undo goes one step');
    await finish(tester);
  });

  testWidgets('⌘N → full form → ⌘↵ saves with every field', (tester) async {
    final app = await pumpApp(tester);
    await cmd(tester, LogicalKeyboardKey.keyN);
    expect(find.byType(TaskEditorPage), findsOneWidget);
    expect(find.text('New Task'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Draft the proposal');
    await tester.tap(find.text('Urgent').first);
    await tester.tap(find.text('In Progress').first);
    await tester.pumpAndSettle();
    await cmd(tester, LogicalKeyboardKey.enter);

    final t = app.store.allTasks.single;
    expect(t.title, 'Draft the proposal');
    expect(t.priority, Priority.urgent);
    expect(t.status, TaskStatus.inProgress);
    expect(t.startedAt, isNotNull);
    expect(
      find.byType(TaskEditorPage),
      findsNothing,
      reason: 'form closes after saving',
    );
    await finish(tester);
  });

  testWidgets('empty title is refused', (tester) async {
    final app = await pumpApp(tester);
    await cmd(tester, LogicalKeyboardKey.keyN);
    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();
    expect(find.text('A title is required'), findsOneWidget);
    expect(app.store.allTasks, isEmpty);
    await finish(tester);
  });

  testWidgets('company workspace: add, start, complete across the three tabs', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await tester.tap(find.text('Company B'));
    await tester.pumpAndSettle();
    expect(app.contextCompanyId, app.store.companies[1].id);

    await tester.enterText(find.byType(TextField).last, 'Ship release');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final t = app.store.allTasks.single;
    expect(
      t.companyId,
      app.store.companies[1].id,
      reason: 'company page pre-selects its company',
    );

    // Its circle starts it; it moves up to In Progress but stays on To Do.
    await tester.tap(find.byType(StatusCircle).first);
    await tester.pumpAndSettle();
    expect(t.status, TaskStatus.inProgress);
    expect(find.text('Ship release'), findsOneWidget);
    expect(find.text('Nothing to do here'), findsNothing);
    await tester.tap(find.text('In Progress').first);
    await tester.pumpAndSettle();
    expect(find.text('Ship release'), findsOneWidget);

    await tester.tap(find.byType(StatusCircle).first);
    await tester.pumpAndSettle();
    expect(t.status, TaskStatus.done);
    expect(find.text('Ship release'), findsOneWidget);
    await tester.tap(find.text('To Do').first);
    await tester.pumpAndSettle();
    expect(find.text('Ship release'), findsOneWidget);
    await tester.tap(find.text('Completed').first);
    await tester.pumpAndSettle();
    expect(find.text('Ship release'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('⌘F search, ⌘1 / ⌘2 lists, esc closes the panel', (tester) async {
    final app = await pumpApp(tester);
    app.store.quickAdd('Renew passport', companyId: app.store.personal.id);
    app.store.quickAdd(
      'Pay rent',
      companyId: app.store.personal.id,
      due: app.store.now,
    );
    await tester.pumpAndSettle();

    await cmd(tester, LogicalKeyboardKey.keyF);
    await tester.enterText(find.byType(TextField).first, 'passport');
    await tester.pumpAndSettle();
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Renew passport'), findsOneWidget);

    await cmd(tester, LogicalKeyboardKey.digit1);
    expect(find.text('All Tasks'), findsOneWidget);
    expect(find.text('Renew passport'), findsOneWidget);
    expect(find.text('Pay rent'), findsOneWidget);

    await cmd(tester, LogicalKeyboardKey.digit2);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Pay rent'), findsOneWidget);
    expect(find.text('Renew passport'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(nativeCalls, contains('hidePanel'));
    await finish(tester);
  });

  testWidgets('delete asks for confirmation and can be undone', (tester) async {
    final app = await pumpApp(tester);
    final t = app.store.quickAdd(
      'Disposable',
      companyId: app.store.personal.id,
      due: app.store.now,
    );
    await tester.pumpAndSettle();
    app.openTask(t);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete task?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(app.store.task(t.id), isNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.store.task(t.id), isNotNull);
    await finish(tester);
  });

  testWidgets('Arabic: right-to-left layout, Arabic text, add and complete', (
    tester,
  ) async {
    final app = await pumpApp(tester, language: AppLanguage.ar);
    final home = tester.element(find.text('الشركات'));
    expect(Directionality.of(home), TextDirection.rtl);
    expect(find.text('الشركة الأولى'), findsOneWidget);
    expect(find.text('شخصي'), findsWidgets);

    // Back button sits on the right in Arabic.
    await tester.tap(find.text('الشركة الثانية'));
    await tester.pumpAndSettle();
    final back = tester.getCenter(find.byIcon(Icons.chevron_left_rounded));
    expect(back.dx, greaterThan(300));

    await tester.enterText(find.byType(TextField).last, 'مراجعة العقد !');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final t = app.store.allTasks.single;
    expect(t.title, 'مراجعة العقد');
    expect(t.priority, Priority.urgent);
    expect(find.text('عاجلة'), findsWidgets);

    await tester.tap(find.byType(StatusCircle).first);
    await tester.pumpAndSettle();
    expect(find.text('نُقلت إلى قيد التنفيذ'), findsOneWidget);
    await tester.tap(find.byType(StatusCircle).first);
    await tester.pumpAndSettle();
    expect(find.text('اكتملت المهمة'), findsOneWidget);
    expect(find.text('تراجع'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'switching language keeps your place and renames default companies',
    (tester) async {
      final app = await pumpApp(tester);
      app.openSettings();
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
      app.setLanguage(AppLanguage.ar);
      await tester.pumpAndSettle();
      expect(
        find.text('الإعدادات'),
        findsWidgets,
        reason: 'still on the settings page',
      );
      expect(app.store.companies.first.name, 'الشركة الأولى');
      app.store.updateCompany(app.store.companies.first, name: 'رِلا');
      app.setLanguage(AppLanguage.en);
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
      expect(
        app.store.companies.first.name,
        'رِلا',
        reason: 'renamed companies are left alone',
      );
      expect(app.store.companies[1].name, 'Company B');
      await finish(tester);
    },
  );

  testWidgets(
    'curtain: columns per company, side pane, drag to start, sheets',
    (tester) async {
      final app = await pumpApp(
        tester,
        mode: DisplayMode.curtain,
        size: const Size(1440, 820),
      );
      final store = app.store;
      expect(find.text('Overview'), findsWidgets);
      // One column per company (sidebar lists them too).
      for (final c in store.companies) {
        expect(find.text(c.name), findsWidgets);
      }

      // Add from Company B's column.
      final b = store.companies[1];
      await tester.enterText(find.byType(TextField).at(2), 'Ship release');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final t = store.allTasks.single;
      expect(t.companyId, b.id);

      // Clicking a task opens the side pane instead of leaving the curtain.
      await tester.tap(find.text('Ship release'));
      await tester.pumpAndSettle();
      expect(app.curtain.taskId, t.id);
      expect(find.byType(TaskEditorPage), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditorPage), findsNothing);

      // Company board: drag the card from To Do into In Progress.
      app.openCompany(b);
      await tester.pumpAndSettle();
      final from = tester.getCenter(find.text('Ship release'));
      final to = tester.getCenter(find.text('Drag a task here to start it'));
      final gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(t.status, TaskStatus.inProgress);

      // Settings opens as a sheet; esc closes the sheet, not the curtain.
      await cmd(tester, LogicalKeyboardKey.comma);
      expect(find.byType(CurtainSheet), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CurtainSheet), findsNothing);
      expect(nativeCalls, isNot(contains('hidePanel')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(nativeCalls, contains('hidePanel'));
      await finish(tester);
    },
  );

  testWidgets(
    'curtain: a ticked task stays at the bottom of its column, crossed out',
    (tester) async {
      final app = await pumpApp(
        tester,
        mode: DisplayMode.curtain,
        size: const Size(1440, 820),
      );
      final store = app.store;
      final b = store.companies[1].id;
      final invoice = store.addTask(
        store.draftTask(companyId: b)..title = 'Send invoice',
      );
      store.addTask(store.draftTask(companyId: b)..title = 'Call supplier');
      await tester.pumpAndSettle();

      Future<void> clickCircle() async {
        await tester.tap(
          find.descendant(
            of: find.widgetWithText(TaskRow, 'Send invoice'),
            matching: find.byType(StatusCircle),
          ),
        );
        await tester.pumpAndSettle();
      }

      // First click: in progress, at the top of the column.
      await clickCircle();
      expect(invoice.status, TaskStatus.inProgress);
      expect(
        tester.getTopLeft(find.text('Send invoice')).dy,
        lessThan(tester.getTopLeft(find.text('Call supplier')).dy),
      );
      // Second click: done.
      await clickCircle();
      expect(invoice.status, TaskStatus.done);

      final title = find.text('Send invoice');
      expect(title, findsOneWidget, reason: 'still in the column');
      expect(
        tester.widget<Text>(title).style?.decoration,
        TextDecoration.lineThrough,
      );
      expect(
        tester.getTopLeft(title).dy,
        greaterThan(tester.getTopLeft(find.text('Call supplier')).dy),
        reason: 'completed tasks sit under the open ones',
      );

      // A third click reopens it.
      await clickCircle();
      expect(invoice.status, TaskStatus.todo);
      store.setStatus(invoice, TaskStatus.done);

      // The setting hides them again.
      store.updateSettings((s) => s.showCompletedInLists = false);
      await tester.pumpAndSettle();
      expect(find.text('Send invoice'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'curtain: session list on the end side — write, tick, stays crossed out',
    (tester) async {
      final app = await pumpApp(
        tester,
        mode: DisplayMode.curtain,
        size: const Size(1440, 820),
      );
      final store = app.store;
      expect(find.text('Plan this session'), findsOneWidget);
      final field = find.descendant(
        of: find.byType(SessionList),
        matching: find.byType(TextField),
      );

      // Enter adds and keeps the field ready for the next line.
      await tester.enterText(field, 'Reply to client emails');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Review the contract');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(store.sessionItems.length, 2);
      expect(store.allTasks, isEmpty, reason: 'not company tasks');
      expect(find.text('0 of 2'), findsOneWidget);

      // It sits at the end edge: right of the columns in English.
      final session = tester.getRect(find.byType(SessionList));
      final column = tester.getRect(find.text('Company A').last);
      expect(session.left, greaterThan(column.right));

      Future<void> clickFirstCircle() async {
        await tester.tap(
          find
              .descendant(
                of: find.byType(SessionList),
                matching: find.byType(StatusDot),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }

      // First click: working on it. Second: done.
      await clickFirstCircle();
      expect(store.sessionItems.first.status, TaskStatus.inProgress);
      expect(find.text('0 of 2'), findsOneWidget);
      await clickFirstCircle();
      final first = store.sessionItems.last;
      expect(first.title, 'Reply to client emails');
      expect(first.done, isTrue);
      expect(find.text('1 of 2'), findsOneWidget);
      final title = find.text('Reply to client emails');
      expect(title, findsOneWidget, reason: 'still listed');
      expect(
        tester.widget<Text>(title).style?.decoration,
        TextDecoration.lineThrough,
      );
      expect(
        tester.getTopLeft(title).dy,
        greaterThan(tester.getTopLeft(find.text('Review the contract')).dy),
      );

      // Click a title to rename it.
      await tester.tap(find.text('Review the contract'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(SessionList),
              matching: find.byType(TextField),
            )
            .first,
        'Review the supplier contract',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Review the supplier contract'), findsOneWidget);

      // The top-bar button hides and shows it.
      await tester.tap(find.byTooltip('Hide session'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionList), findsNothing);
      await tester.tap(find.byTooltip('Show session'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionList), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('curtain search filters the columns live', (tester) async {
    final app = await pumpApp(
      tester,
      mode: DisplayMode.curtain,
      size: const Size(1440, 820),
    );
    app.store.quickAdd('Renew passport', companyId: app.store.personal.id);
    app.store.quickAdd('Pay rent', companyId: app.store.personal.id);
    await tester.pumpAndSettle();
    await cmd(tester, LogicalKeyboardKey.keyF);
    await tester.enterText(find.byType(TextField).first, 'passport');
    await tester.pumpAndSettle();
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Renew passport'), findsOneWidget);
    expect(find.text('Pay rent'), findsNothing);
    await finish(tester);
  });

  testWidgets('switching to the curtain keeps Settings open and tells macOS', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    app.openSettings();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Curtain'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Curtain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Curtain'));
    await tester.pumpAndSettle();
    expect(app.isCurtain, isTrue);
    expect(
      find.byType(CurtainSheet),
      findsOneWidget,
      reason: 'settings re-opened as a sheet',
    );
    await tester.scrollUntilVisible(
      find.text('Transparency'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CurtainSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Transparency'), findsOneWidget);
    expect(nativeCalls, contains('setDisplayMode'));
    await finish(tester);
  });

  testWidgets('small mode shows the summary and urgent tasks only', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      mode: DisplayMode.small,
      size: const Size(360, 500),
    );
    app.store.quickAdd('Call the bank !', companyId: app.store.personal.id);
    app.store.quickAdd('Someday', companyId: app.store.personal.id);
    await tester.pumpAndSettle();
    expect(find.text('Call the bank'), findsOneWidget);
    expect(find.text('Someday'), findsNothing);
    expect(find.text('Companies'), findsNothing);
    await finish(tester);
  });
}

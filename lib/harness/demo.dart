import '../core/dates.dart';
import '../data/models.dart';
import '../data/persistence.dart';
import '../data/settings.dart';
import '../data/store.dart';

/// Demo mode (`DOCKET_DEMO=1`): a throwaway data folder filled with English
/// sample tasks for screenshots, worded as projects. Looks like the user's
/// own setup (display mode, language, theme, curtain), but never schedules
/// notifications, backs up, or touches the login item — and never opens the
/// real tasks.
Future<void> prepareDemo(
  TaskStore store, {
  required String realDatabase,
}) async {
  AppSettings? real;
  try {
    final db = await SqlitePersistence.open(realDatabase);
    real = AppSettings.fromJson(await db.loadSettings());
    await db.close();
  } catch (_) {
    // No real database yet: defaults are fine.
  }

  store.updateSettings((s) {
    if (real != null) {
      s
        ..language = real.language
        ..themeMode = real.themeMode
        ..use24h = real.use24h
        ..sortMode = real.sortMode
        ..badgeMode = real.badgeMode
        ..displayMode = real.displayMode
        ..curtainTransparency = real.curtainTransparency
        ..curtainBlur = real.curtainBlur
        ..curtainHeight = real.curtainHeight
        ..curtainAnimation = real.curtainAnimation
        ..curtainTone = real.curtainTone
        ..curtainShowSession = real.curtainShowSession
        ..showSummary = real.showSummary
        ..showCompanies = real.showCompanies
        ..showToday = real.showToday
        ..showCompletedInLists = real.showCompletedInLists
        ..hotkeysEnabled = real.hotkeysEnabled
        ..toggleHotKey = real.toggleHotKey
        ..quickAddHotKey = real.quickAddHotKey;
    }
    s
      ..notificationsEnabled = false
      ..autoBackup = false
      ..launchAtLoginInitialized = true
      ..welcomeDismissed = true;
  });

  // Sample names stay as written in either interface language.
  store.localizeNames = false;
  store.updateSettings((s) => s.useProjects = true);
  seedShowcase(store);
}

/// English sample data for screenshots: a team lead's week across three
/// projects plus Personal — PRs, TestFlight builds, sprint rituals, 1:1s —
/// with every state the screens show (urgent, overdue, due today, in
/// progress with a timer and subtasks, recurring, completed today) and a
/// session list under way.
void seedShowcase(TaskStore store) {
  final now = store.now;
  final today = dateOnly(now);
  final cs = store.companies;
  store.updateCompany(cs[0], name: 'Project One', icon: 'rocket');
  store.updateCompany(cs[1], name: 'Project Two', icon: 'code');
  store.updateCompany(cs[2], name: 'Project Three', icon: 'chart');
  store.updateCompany(cs[3], name: 'Personal');
  final one = cs[0].id, two = cs[1].id, three = cs[2].id, me = cs[3].id;

  Task add(
    String project,
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
  }) {
    final t = store.draftTask(companyId: project)
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
    return saved;
  }

  // Finished today first, so they sit under the open tasks. Within each
  // project the task added last shows on top.
  add(one, 'Ship 3.1.4 hotfix to the App Store', status: TaskStatus.done);
  add(
    one,
    'Merge release/3.2 into main',
    status: TaskStatus.done,
    tags: ['git'],
  );
  add(two, 'Deploy API v3 to staging', status: TaskStatus.done);
  add(three, 'Approve dashboard designs', status: TaskStatus.done);
  add(me, 'Book dentist appointment', status: TaskStatus.done);

  // Project One — the mobile app
  add(one, 'Clean up feature flags after launch', priority: Priority.low);
  add(one, 'Write release notes for 3.2', dueIn: 1, tags: ['release']);
  add(
    one,
    'Review PR #214 — payments refactor',
    dueIn: 0,
    minutes: 16 * 60 + 30,
    tags: ['review'],
  );
  add(
    one,
    'Fix iOS 18 login crash',
    description: 'Crashlytics: 312 users affected since 3.1.4',
    priority: Priority.urgent,
    dueIn: -1,
    tags: ['bug'],
  );
  final testFlight = add(
    one,
    'Push 3.2.0 to TestFlight',
    description: 'Bump the build, upload, and brief the testers',
    priority: Priority.urgent,
    status: TaskStatus.inProgress,
    dueIn: 0,
    minutes: 18 * 60,
    tags: ['release', 'ios'],
    subtasks: [
      'Bump version to 3.2.0 (412)',
      'Archive and upload',
      'Write notes for testers',
      'Invite the QA group',
      'Smoke test on device',
    ],
    doneSubtasks: 3,
  );
  store.updateTask(testFlight, (t) {
    t.timeSpentSeconds = 80 * 60;
    t.expectedDate = addDays(today, 1);
    t.notes =
        'Wait for Sara to sign off the payments flow before inviting '
        'external testers.';
  });
  store.addUpdate(testFlight, 'Build 411 rejected: missing privacy manifest');
  store.addUpdate(testFlight, 'Privacy manifest added, build 412 processing');

  // Project Two — the backend
  add(two, 'Upgrade CI runners to Node 22', priority: Priority.low);
  add(
    two,
    'Write RFC: offline sync',
    description: 'Conflict resolution, queueing and retry policy',
    dueIn: 3,
    tags: ['rfc'],
  );
  add(
    two,
    'Sprint planning',
    dueIn: 2,
    minutes: 10 * 60,
    recurrence: Recurrence.weekly,
  );
  add(
    two,
    'Migrate auth to Firebase App Check',
    status: TaskStatus.inProgress,
    dueIn: 2,
    tags: ['security'],
    subtasks: [
      'Enable App Check in console',
      'Ship iOS attestation',
      'Ship Android Play Integrity',
      'Enforce on the API',
    ],
    doneSubtasks: 2,
  );
  add(two, 'Unblock Omar on rate limits', priority: Priority.urgent, dueIn: 0);

  // Project Three — the web dashboard
  add(three, 'Interview: Flutter developer', dueIn: 4, minutes: 13 * 60);
  add(
    three,
    '1:1 with Sara',
    dueIn: 1,
    minutes: 11 * 60,
    recurrence: Recurrence.weekly,
  );
  add(
    three,
    'Triage new Crashlytics issues',
    recurrence: Recurrence.daily,
    dueIn: 0,
  );
  add(
    three,
    'Review dashboard PR #87',
    dueIn: -1,
    minutes: 11 * 60,
    tags: ['review'],
  );

  // Personal
  add(me, 'Renew passport', priority: Priority.low, dueIn: 12);
  add(me, 'Gym', dueIn: 0, minutes: 20 * 60, recurrence: Recurrence.daily);
  add(me, 'Call mom', dueIn: 0, minutes: 19 * 60);

  // Session list under way: one in hand, two left, two done.
  final emails = store.addSessionItem('Reply to client emails')!;
  final review = store.addSessionItem('Review PR #214')!;
  store.addSessionItem('Upload build 412 to TestFlight');
  store.addSessionItem('Unblock Omar on rate limits');
  final standup = store.addSessionItem('Post standup notes')!;
  for (final i in [emails, emails, standup, standup, review]) {
    store.advanceSessionItem(i);
  }
  store.updateSettings(
    (s) => s.sessionStartedAt = now.subtract(const Duration(minutes: 50)),
  );
}

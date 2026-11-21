import 'dart:async';

import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/native.dart';
import '../data/backup.dart';
import '../data/models.dart';
import '../data/queries.dart';
import '../data/settings.dart';
import '../data/store.dart';
import '../l10n/l10n.dart';
import '../services/hotkeys.dart';
import '../services/reminders.dart';
import 'pages/company_edit_page.dart';
import 'pages/curtain_page.dart';
import 'pages/company_page.dart';
import 'pages/quick_add_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/task_editor_page.dart';
import 'pages/task_list_page.dart';
import 'widgets/dialogs.dart';
import 'widgets/toast.dart';

/// UI-level coordinator: in-panel navigation, panel lifecycle, the badge, and
/// task actions that need confirmation or undo.
class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.backups,
    required this.reminders,
    required this.hotkeys,
    Native? native,
  }) : native = native ?? Native.instance;

  final TaskStore store;
  final BackupService backups;
  final ReminderService reminders;
  final HotKeyService hotkeys;
  final Native native;

  final navigatorKey = GlobalKey<NavigatorState>();

  /// What the curtain shows (view, selected task, search).
  final curtain = CurtainState();
  final toasts = ToastController();

  /// Bumped when the home screen should scroll back to the top.
  final homeReset = ValueNotifier<int>(0);

  /// Company of the page in front, used to pre-fill ⌘N.
  String? contextCompanyId;

  /// Task under the pointer or open in the editor, used by ⌘↵.
  String? activeTaskId;

  bool panelVisible = false;

  /// True while the panel is open only because of the Quick Add shortcut;
  /// saving then hides the panel and returns you to what you were doing.
  bool quickAddFromHotkey = false;

  DateTime? _hiddenAt;
  Timer? _minuteTimer;
  DateTime _lastTick = DateTime.now();
  String _lastBadge = '';

  NavigatorState? get _nav => navigatorKey.currentState;

  void start() {
    native.onPanelShow = onPanelShow;
    native.onPanelHide = onPanelHide;
    native.onNotificationAction = _onNotificationAction;
    store.addListener(_updateBadge);
    _updateBadge();
    applyDisplayMode();
    _applyNativeStrings();
    _minuteTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    store.removeListener(_updateBadge);
    super.dispose();
  }

  void _tick() {
    final now = DateTime.now();
    if (now.minute != _lastTick.minute || !sameDay(now, _lastTick)) {
      final dayChanged = !sameDay(now, _lastTick);
      _lastTick = now;
      store.tick();
      if (dayChanged) {
        reminders.sync();
        backups.autoBackupIfDue();
      }
    }
  }

  void _updateBadge() {
    final count = store.badgeCount(store.settings.badgeMode);
    final text = count > 0 ? '$count' : '';
    if (text != _lastBadge) {
      _lastBadge = text;
      native.setBadge(text);
    }
  }

  bool get isCurtain => store.settings.displayMode.isCurtain;

  /// Glass tint actually in effect ("auto" resolves to the app's theme).
  String get glassTone {
    final s = store.settings;
    if (s.curtainTone != GlassTone.auto) return s.curtainTone.key;
    return switch (s.themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'auto',
    };
  }

  /// Sends the display mode and curtain style to the native window (live).
  void applyDisplayMode() {
    final s = store.settings;
    native.setDisplayMode(
      curtain: s.displayMode.isCurtain,
      width: s.displayMode.isCurtain
          ? DisplayMode.normal.width
          : s.displayMode.width,
      height: s.displayMode.isCurtain
          ? DisplayMode.normal.height
          : s.displayMode.height,
      curtainHeight: s.curtainHeight,
      animated: s.curtainAnimation,
      blur: s.curtainBlur,
      tone: glassTone,
    );
  }

  /// Switches between the drop-down sizes and the curtain. Open pages are
  /// re-presented in the new style (Settings stays open for live preview).
  void setDisplayMode(DisplayMode mode) {
    if (store.settings.displayMode == mode) return;
    final wasSettings = _isTop('settings');
    _nav?.popUntil((r) => r.isFirst);
    curtain.reset();
    store.updateSettings((s) => s.displayMode = mode);
    applyDisplayMode();
    if (wasSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openSettings());
    }
  }

  /// Switches the interface language everywhere, including the menu bar menu,
  /// notification actions and not-yet-renamed default company names.
  void setLanguage(AppLanguage language) {
    if (store.settings.language == language) return;
    L10n.current = language;
    store.updateSettings((s) => s.language = language);
    store.localizeDefaultNames(language);
    _applyNativeStrings();
    reminders.sync();
  }

  void _applyNativeStrings() {
    native.setLocalizedStrings({
      'open': tr('Open Docket'),
      'quickAdd': tr('Quick Add…'),
      'settings': tr('Settings…'),
      'quit': tr('Quit Docket'),
      'markDone': tr('Mark as Done'),
    });
  }

  void settingsChanged({bool display = false, bool hotkeys = false}) {
    if (display) applyDisplayMode();
    if (hotkeys) this.hotkeys.apply();
    _updateBadge();
    reminders.sync();
  }

  // ---------------------------------------------------------------------------
  // Panel lifecycle
  // ---------------------------------------------------------------------------

  void onPanelShow(String reason) {
    final wasVisible = panelVisible;
    panelVisible = true;
    final hiddenFor = _hiddenAt == null
        ? Duration.zero
        : DateTime.now().difference(_hiddenAt!);
    if (!wasVisible && hiddenFor > const Duration(minutes: 2)) {
      goHome();
    }
    if (reason == 'quickAdd') {
      openQuickAdd(fromHotkey: !wasVisible);
    } else if (reason == 'settings') {
      openSettings();
    } else if (reason.startsWith('task:')) {
      final t = store.task(reason.substring(5));
      if (t != null) {
        goHome();
        openTask(t);
      }
    }
    notifyListeners();
  }

  void onPanelHide() {
    panelVisible = false;
    _hiddenAt = DateTime.now();
    activeTaskId = null;
    if (_isTop('quickAdd')) _nav?.pop();
    quickAddFromHotkey = false;
    toasts.dismiss();
    store.flush();
    notifyListeners();
  }

  void hidePanel() => native.hidePanel();

  void _onNotificationAction(String action, String taskId) {
    final t = store.task(taskId);
    if (t == null) return;
    if (action == 'complete' && t.isOpen) store.setStatus(t, TaskStatus.done);
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  String? _topName;

  bool _isTop(String name) => _topName == name;

  /// Called by [RouteTracker].
  void routeChanged(String? topName) => _topName = topName;

  /// In the curtain, pages open as centred sheets over the glass.
  Future<T?> push<T>(String name, Widget page) {
    return _nav!.push<T>(
      PanelRoute<T>(name: name, child: page, sheet: isCurtain),
    );
  }

  /// Opens a top-level destination from anywhere (⌘1, ⌘2, …) without stacking duplicates.
  void goTo(String name, Widget page) {
    if (_isTop(name)) return;
    _nav?.popUntil((r) => r.isFirst);
    push(name, page);
  }

  void goHome() {
    _nav?.popUntil((r) => r.isFirst);
    homeReset.value++;
    curtain.reset();
  }

  /// Closes sheets over the curtain without touching its view.
  void _toCurtain() => _nav?.popUntil((r) => r.isFirst);

  void back() {
    _nav?.maybePop();
  }

  void openCompany(Company c, {TaskStatus tab = TaskStatus.todo}) {
    if (isCurtain) {
      _toCurtain();
      curtain.showCompany(c.id);
      return;
    }
    push('company:${c.id}', CompanyPage(companyId: c.id, initialTab: tab));
  }

  /// Drop-down: a page. Curtain: the detail pane beside the board.
  void openTask(Task t) {
    if (isCurtain) {
      _toCurtain();
      curtain.openTask(t.id);
      return;
    }
    if (_isTop('task:${t.id}')) return;
    push('task:${t.id}', TaskEditorPage(taskId: t.id));
  }

  void newTask({String? companyId, TaskStatus? status, String title = ''}) {
    if (_isTop('newTask')) return;
    push(
      'newTask',
      TaskEditorPage.create(
        companyId: companyId ?? contextCompanyId,
        status: status,
        initialTitle: title,
      ),
    );
  }

  void openQuickAdd({bool fromHotkey = false}) {
    quickAddFromHotkey = fromHotkey;
    if (_isTop('quickAdd')) return;
    push('quickAdd', QuickAddPage(companyId: contextCompanyId));
  }

  void openSearch() {
    if (isCurtain) {
      _toCurtain();
      curtain.focusSearch();
      return;
    }
    if (_isTop('search')) return;
    push('search', const SearchPage());
  }

  void openList(ListKind kind) {
    if (isCurtain) {
      _toCurtain();
      curtain.showList(kind);
      return;
    }
    goTo('list:${kind.name}', TaskListPage(kind: kind));
  }

  void openSettings() => goTo('settings', const SettingsPage());

  void editCompany(Company? c) =>
      push('companyEdit:${c?.id ?? 'new'}', CompanyEditPage(companyId: c?.id));

  // ---------------------------------------------------------------------------
  // Task actions with feedback
  // ---------------------------------------------------------------------------

  void setStatus(Task t, TaskStatus status) {
    final change = store.setStatus(t, status);
    if (change == null) return;
    if (status == TaskStatus.done) {
      final next = change.spawned;
      toasts.show(
        next == null
            ? tr('Task completed')
            : tr('Completed · next one {when}', {
                'when': formatRelativeDay(
                  next.dueDate!,
                  store.now,
                ).toLowerCase(),
              }),
        actionLabel: tr('Undo'),
        onAction: () => store.undoStatus(change),
      );
    } else if (change.previousStatus == TaskStatus.done) {
      toasts.show(
        tr('Reopened'),
        actionLabel: tr('Undo'),
        onAction: () => store.undoStatus(change),
      );
    } else if (status == TaskStatus.inProgress) {
      toasts.show(
        tr('Moved to In Progress'),
        actionLabel: tr('Undo'),
        onAction: () => store.undoStatus(change),
      );
    } else {
      toasts.show(
        tr('Moved to To Do'),
        actionLabel: tr('Undo'),
        onAction: () => store.undoStatus(change),
      );
    }
  }

  /// The status circle: open → completed, completed → reopened.
  void toggleDone(Task t) =>
      setStatus(t, t.isDone ? TaskStatus.todo : TaskStatus.done);

  /// ⌘↵
  void completeActive() {
    final t = store.task(activeTaskId);
    if (t == null) return;
    toggleDone(t);
  }

  Future<bool> deleteTask(
    BuildContext context,
    Task t, {
    bool popOnDelete = false,
  }) async {
    final ok = await confirmDialog(
      context,
      title: tr('Delete task?'),
      message: tr('“{title}” will be deleted. You can undo right after.', {
        'title': t.title,
      }),
      confirmLabel: tr('Delete'),
      destructive: true,
    );
    if (!ok) return false;
    if (popOnDelete) _nav?.maybePop();
    store.delete(t);
    toasts.show(
      tr('Task deleted'),
      actionLabel: tr('Undo'),
      onAction: () => store.restore(t),
    );
    return true;
  }

  Future<bool> deleteMany(BuildContext context, List<Task> tasks) async {
    if (tasks.isEmpty) return false;
    final ok = await confirmDialog(
      context,
      title: tasks.length == 1
          ? tr('Delete 1 task?')
          : tr('Delete {n} tasks?', {'n': tasks.length}),
      message: tr('You can undo right after.'),
      confirmLabel: tr('Delete'),
      destructive: true,
    );
    if (!ok) return false;
    store.deleteMany(tasks);
    toasts.show(
      tr('{n} deleted', {'n': tasks.length}),
      actionLabel: tr('Undo'),
      onAction: () => store.restoreMany(tasks),
    );
    return true;
  }

  void archive(Task t, {bool popAfter = false}) {
    if (popAfter) _nav?.maybePop();
    store.setArchived(t, true);
    toasts.show(
      tr('Task archived'),
      actionLabel: tr('Undo'),
      onAction: () => store.setArchived(t, false),
    );
  }

  void unarchive(Task t) {
    store.setArchived(t, false);
    toasts.show(tr('Restored from archive'));
  }

  void duplicate(Task t, {bool open = false}) {
    final copy = store.duplicate(t);
    if (open && isCurtain) {
      curtain.openTask(copy.id);
      toasts.show(tr('Duplicated — editing the copy'));
    } else if (open) {
      _nav?.pushReplacement(
        PanelRoute(
          name: 'task:${copy.id}',
          child: TaskEditorPage(taskId: copy.id),
        ),
      );
      toasts.show(tr('Duplicated — editing the copy'));
    } else {
      toasts.show(
        tr('Duplicated'),
        actionLabel: tr('Open'),
        onAction: () => openTask(copy),
      );
    }
  }

  void setPriority(Task t, Priority p) => store.setPriority(t, p);

  void moveTo(Task t, Company c) {
    store.moveToCompany(t, c.id);
    toasts.show(tr('Moved to {company}', {'company': c.name}));
  }

  Future<void> quit() async {
    await store.flush();
    await store.flushSettings();
    await native.quit();
  }
}

/// Fast, subtle page transition for the panel (slide 12pt + fade).
class PanelRoute<T> extends PageRouteBuilder<T> {
  PanelRoute({required String name, required Widget child, bool sheet = false})
    : super(
        settings: RouteSettings(name: name),
        opaque: !sheet,
        barrierDismissible: sheet,
        barrierColor: sheet ? const Color(0x24000000) : null,
        barrierLabel: sheet ? 'Close' : null,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (context, animation, secondary) =>
            sheet ? CurtainSheet(child: child) : child,
        transitionsBuilder: (context, animation, secondary, child) {
          if (sheet) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween(begin: 0.97, end: 1.0).animate(curved),
                child: child,
              ),
            );
          }
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                // Pages slide in from the reading direction's end.
                begin: Offset(
                  Directionality.of(context) == TextDirection.rtl
                      ? -0.04
                      : 0.04,
                  0,
                ),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}

enum CurtainView { overview, list, company }

/// Navigation inside the curtain, which shows everything on one screen.
class CurtainState extends ChangeNotifier {
  CurtainView view = CurtainView.overview;
  ListKind list = ListKind.today;
  String? companyId;

  /// Task open in the detail pane.
  String? taskId;
  String query = '';
  final searchFocus = FocusNode(debugLabel: 'curtain search');
  final searchController = TextEditingController();

  void showOverview() {
    view = CurtainView.overview;
    companyId = null;
    notifyListeners();
  }

  void showList(ListKind kind) {
    if (kind == ListKind.all) return showOverview();
    view = CurtainView.list;
    list = kind;
    companyId = null;
    notifyListeners();
  }

  void showCompany(String id) {
    view = CurtainView.company;
    companyId = id;
    notifyListeners();
  }

  void openTask(String id) {
    taskId = id;
    notifyListeners();
  }

  void closeTask() {
    taskId = null;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void focusSearch() => searchFocus.requestFocus();

  void reset() {
    view = CurtainView.overview;
    companyId = null;
    taskId = null;
    query = '';
    searchController.clear();
    notifyListeners();
  }
}

/// Keeps [AppController] informed of the route in front.
class RouteTracker extends NavigatorObserver {
  RouteTracker(this.app);
  final AppController app;
  final _stack = <Route<dynamic>>[];

  /// A menu, picker or dialog is in front.
  bool get topIsPopup => _stack.isNotEmpty && _stack.last is PopupRoute;

  void _update() {
    final pages = _stack.whereType<PageRoute<dynamic>>();
    app.routeChanged(pages.isEmpty ? null : pages.last.settings.name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _update();
  }
}

/// Gives every widget access to the controller.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.app, required super.child});
  final AppController app;

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.app;

  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.app;

  @override
  bool updateShouldNotify(AppScope oldWidget) => app != oldWidget.app;
}

extension AppContext on BuildContext {
  AppController get app => AppScope.read(this);
  TaskStore get store => AppScope.read(this).store;
}

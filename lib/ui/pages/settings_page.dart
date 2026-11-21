import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../data/backup.dart';
import '../../data/queries.dart';
import '../../data/settings.dart';
import '../../services/hotkeys.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/menus.dart';
import '../widgets/pickers.dart';
import 'task_list_page.dart';
import '../../l10n/l10n.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _notificationStatus = 'unknown';
  String _loginStatus = 'unknown';
  Map<String, String> _info = {};
  List<BackupFile> _backups = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final app = context.app;
    final results = await Future.wait([
      app.native.notificationStatus(),
      app.native.launchAtLogin(),
    ]);
    final info = await app.native.appInfo();
    final backups = await app.backups.list();
    if (!mounted) return;
    setState(() {
      _notificationStatus = results[0];
      _loginStatus = results[1];
      _info = info;
      _backups = backups;
    });
  }

  void _set(
    void Function(AppSettings s) edit, {
    bool display = false,
    bool hotkeys = false,
  }) {
    final app = context.app;
    app.store.updateSettings(edit);
    app.settingsChanged(display: display, hotkeys: hotkeys);
  }

  /// Slider drags apply live; the value is saved when the drag ends.
  void _live(void Function(AppSettings s) edit, {bool native = false}) {
    final app = context.app;
    app.store.updateSettings(edit, persist: false);
    if (native) app.applyDisplayMode();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return StoreBuilder(
      builder: (context) {
        final s = app.store.settings;
        return PanelPage(
          title: tr('Settings'),
          body: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 24),
            children: [
              _companies(),
              _shortcuts(s),
              _notifications(s),
              _appearance(s),
              _menuBar(s),
              _backup(s),
              _general(),
            ],
          ),
        );
      },
    );
  }

  // Companies -------------------------------------------------------------------

  Widget _companies() {
    final app = context.app;
    final p = context.palette;
    final store = app.store;
    final counts = store.countsByCompany();
    final companies = store.companies;
    return _Group(
      title: tr('Companies'),
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: companies.length,
          onReorderItem: store.moveCompany,
          proxyDecorator: (child, i, a) => Material(
            color: p.raised,
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
          itemBuilder: (context, i) {
            final c = companies[i];
            final n = counts[c.id];
            return Hoverable(
              key: ValueKey(c.id),
              onTap: () => app.editCompany(c),
              builder: (context, hovered, _) => Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: hovered ? p.hover : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 15,
                          color: hovered ? p.textTertiary : Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    CompanyAvatar(company: c, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AutoText(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.body.copyWith(color: p.text),
                      ),
                    ),
                    Text(
                      tr('{n} open', {'n': n?.open ?? 0}),
                      style: Type.caption.copyWith(color: p.textTertiary),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: p.textTertiary,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        _Divider(),
        _ActionRow(
          icon: Icons.add_rounded,
          label: tr('Add company'),
          onTap: () => app.editCompany(null),
        ),
      ],
    );
  }

  // Shortcuts --------------------------------------------------------------------

  Widget _shortcuts(AppSettings s) {
    final app = context.app;
    final p = context.palette;
    return ListenableBuilder(
      listenable: app.hotkeys,
      builder: (context, _) {
        final status = app.hotkeys.status;
        return _Group(
          title: tr('Keyboard'),
          children: [
            _Row(
              label: tr('Global shortcuts'),
              sub: tr('Work from any app, even when Docket is closed'),
              trailing: MiniSwitch(
                value: s.hotkeysEnabled,
                onChanged: (v) =>
                    _set((s) => s.hotkeysEnabled = v, hotkeys: true),
              ),
            ),
            _Row(
              label: tr('Open Docket'),
              sub: HotKeyService.describe(status[HotKeyService.toggleId]),
              subColor: p.urgent,
              trailing: _ShortcutRecorder(
                value: s.toggleHotKey,
                enabled: s.hotkeysEnabled,
                fallback: HotKey.defaultToggle,
                other: s.quickAddHotKey,
                onChanged: (k) =>
                    _set((s) => s.toggleHotKey = k, hotkeys: true),
              ),
            ),
            _Row(
              label: tr('Quick Add'),
              sub: HotKeyService.describe(status[HotKeyService.quickAddId]),
              subColor: p.urgent,
              trailing: _ShortcutRecorder(
                value: s.quickAddHotKey,
                enabled: s.hotkeysEnabled,
                fallback: HotKey.defaultQuickAdd,
                other: s.toggleHotKey,
                onChanged: (k) =>
                    _set((s) => s.quickAddHotKey = k, hotkeys: true),
              ),
            ),
            _Divider(),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
              child: Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _KeyLegend('⌘N', tr('New task')),
                  _KeyLegend('⌘F', tr('Search')),
                  _KeyLegend('⌘↵', tr('Complete')),
                  _KeyLegend('esc', tr('Close')),
                  _KeyLegend('⌘1', tr('All tasks')),
                  _KeyLegend('⌘2', tr('Today')),
                  _KeyLegend('⌘3', tr('Overdue')),
                  _KeyLegend('⌘0', tr('Home')),
                  _KeyLegend('⌘[', tr('Back')),
                  _KeyLegend('⌘,', tr('Settings')),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Notifications -----------------------------------------------------------------

  Widget _notifications(AppSettings s) {
    final app = context.app;
    final p = context.palette;
    final denied = _notificationStatus == 'denied';
    final undetermined = _notificationStatus == 'notDetermined';
    final on = s.notificationsEnabled;
    return _Group(
      title: tr('Notifications'),
      children: [
        if (denied || undetermined)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 6),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  size: 16,
                  color: p.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    denied
                        ? tr(
                            'Notifications are turned off for Docket in macOS.',
                          )
                        : tr('Docket needs permission to remind you.'),
                    style: Type.small.copyWith(color: p.textSecondary),
                  ),
                ),
                DButton(
                  label: denied ? tr('Open Settings') : tr('Allow'),
                  dense: true,
                  kind: ButtonKind.primary,
                  onTap: () async {
                    if (denied) {
                      await app.native.openNotificationSettings();
                    } else {
                      await app.native.requestNotificationPermission();
                    }
                    _refresh();
                  },
                ),
              ],
            ),
          ),
        _Row(
          label: tr('Reminders'),
          trailing: MiniSwitch(
            value: on,
            onChanged: (v) => _set((s) => s.notificationsEnabled = v),
          ),
        ),
        _Row(
          label: tr('When a task is due'),
          enabled: on,
          trailing: MiniSwitch(
            value: s.notifyAtDue,
            onChanged: on ? (v) => _set((s) => s.notifyAtDue = v) : null,
          ),
        ),
        _Row(
          label: tr('Remind me before'),
          enabled: on,
          trailing: _MenuButton<int>(
            enabled: on,
            value: s.remindBefore,
            options: {
              0: tr('Off'),
              5: tr('5 minutes'),
              15: tr('15 minutes'),
              30: tr('30 minutes'),
              60: tr('1 hour'),
              120: tr('2 hours'),
              1440: tr('1 day'),
            },
            onChanged: (v) => _set((s) => s.remindBefore = v),
          ),
        ),
        _Row(
          label: tr('Morning summary'),
          sub: tr(
            'Overdue, urgent and due-today counts. Date-only tasks remind at this time too.',
          ),
          enabled: on,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuButton<int>(
                enabled: on && s.dailyDigest,
                value: s.digestMinutes,
                options: {
                  for (var h = 6; h <= 11; h++) ...{
                    h * 60: formatTimeOfDay(h * 60, use24h: s.use24h),
                    h * 60 + 30: formatTimeOfDay(h * 60 + 30, use24h: s.use24h),
                  },
                },
                onChanged: (v) => _set((s) => s.digestMinutes = v),
              ),
              const SizedBox(width: 8),
              MiniSwitch(
                value: s.dailyDigest,
                onChanged: on ? (v) => _set((s) => s.dailyDigest = v) : null,
              ),
            ],
          ),
        ),
        _Row(
          label: tr('Nudge about urgent tasks'),
          sub: tr('Between 9 AM and 6 PM while urgent tasks are open'),
          enabled: on,
          trailing: _MenuButton<int>(
            enabled: on,
            value: s.urgentNudgeHours,
            options: {
              0: tr('Off'),
              1: tr('Every hour'),
              2: tr('Every 2 hours'),
              3: tr('Every 3 hours'),
              4: tr('Every 4 hours'),
            },
            onChanged: (v) => _set((s) => s.urgentNudgeHours = v),
          ),
        ),
      ],
    );
  }

  // Appearance --------------------------------------------------------------------

  Widget _appearance(AppSettings s) {
    return _Group(
      title: tr('Appearance'),
      children: [
        _Row(
          // Both names, so the row is findable whichever language is on screen.
          label: L10n.isArabic ? 'اللغة · Language' : 'Language · اللغة',
          trailing: SizedBox(
            width: 190,
            child: Segmented<AppLanguage>(
              options: AppLanguage.values,
              value: s.language,
              height: 26,
              onChanged: context.app.setLanguage,
              labels: (l, selected) => Text(
                l.nativeName,
                style: Type.small.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        _Row(
          label: tr('Theme'),
          trailing: SizedBox(
            width: 190,
            child: Segmented<ThemeMode>(
              options: const [
                ThemeMode.system,
                ThemeMode.light,
                ThemeMode.dark,
              ],
              value: s.themeMode,
              height: 26,
              onChanged: (m) => _set((s) => s.themeMode = m, display: true),
              labels: (m, selected) => Text(
                switch (m) {
                  ThemeMode.system => tr('Auto'),
                  ThemeMode.light => tr('Light'),
                  ThemeMode.dark => tr('Dark'),
                },
                style: Type.small.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        _DisplayModePicker(
          value: s.displayMode,
          onChanged: (m) => context.app.setDisplayMode(m),
        ),
        if (s.displayMode.isCurtain) ..._curtainRows(s),
        _Row(
          label: tr('24-hour time'),
          trailing: MiniSwitch(
            value: s.use24h,
            onChanged: (v) => _set((s) => s.use24h = v),
          ),
        ),
        _Row(
          label: tr('Default sort'),
          sub: tr('Manual lets you drag tasks into order'),
          trailing: _MenuButton<SortMode>(
            value: s.sortMode,
            options: {for (final m in SortMode.values) m: m.label},
            onChanged: (v) => _set((s) => s.sortMode = v),
          ),
        ),
      ],
    );
  }

  List<Widget> _curtainRows(AppSettings s) => [
    _SliderRow(
      label: tr('Transparency'),
      value: s.curtainTransparency,
      display: '${(s.curtainTransparency * 100).round()}%',
      onChanged: (v) => _live((s) => s.curtainTransparency = v),
      onChangeEnd: (v) => _set((s) => s.curtainTransparency = v),
    ),
    _SliderRow(
      label: tr('Blur'),
      value: s.curtainBlur,
      display: '${(s.curtainBlur * 100).round()}%',
      onChanged: (v) => _live((s) => s.curtainBlur = v, native: true),
      onChangeEnd: (v) => _set((s) => s.curtainBlur = v, display: true),
    ),
    _SliderRow(
      label: tr('Curtain height'),
      value: s.curtainHeight,
      min: 0.45,
      max: 1,
      display: '${(s.curtainHeight * 100).round()}%',
      onChanged: (v) => _live((s) => s.curtainHeight = v, native: true),
      onChangeEnd: (v) => _set((s) => s.curtainHeight = v, display: true),
    ),
    _Row(
      label: tr('Glass'),
      trailing: SizedBox(
        width: 190,
        child: Segmented<GlassTone>(
          options: GlassTone.values,
          value: s.curtainTone,
          height: 26,
          onChanged: (v) => _set((s) => s.curtainTone = v, display: true),
          labels: (v, selected) => Text(
            v.label,
            style: Type.small.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
    _Row(
      label: tr('Slide animation'),
      trailing: MiniSwitch(
        value: s.curtainAnimation,
        onChanged: (v) => _set((s) => s.curtainAnimation = v, display: true),
      ),
    ),
  ];

  // Menu bar --------------------------------------------------------------------

  Widget _menuBar(AppSettings s) {
    final app = context.app;
    return _Group(
      title: tr('Menu Bar'),
      children: [
        _Row(
          label: tr('Count next to icon'),
          trailing: _MenuButton<BadgeMode>(
            value: s.badgeMode,
            options: {for (final m in BadgeMode.values) m: m.label},
            onChanged: (v) => _set((s) => s.badgeMode = v),
          ),
        ),
        _Row(
          label: tr('Show overview'),
          trailing: MiniSwitch(
            value: s.showSummary,
            onChanged: (v) => _set((s) => s.showSummary = v),
          ),
        ),
        _Row(
          label: tr('Show companies'),
          trailing: MiniSwitch(
            value: s.showCompanies,
            onChanged: (v) => _set((s) => s.showCompanies = v),
          ),
        ),
        _Row(
          label: tr('Show today’s tasks'),
          trailing: MiniSwitch(
            value: s.showToday,
            onChanged: (v) => _set((s) => s.showToday = v),
          ),
        ),
        _Row(
          label: tr('Keep completed tasks in lists'),
          sub: tr('Ticked and crossed out at the bottom of each list'),
          trailing: MiniSwitch(
            value: s.showCompletedInLists,
            onChanged: (v) => _set((s) => s.showCompletedInLists = v),
          ),
        ),
        _Divider(),
        _ActionRow(
          icon: Icons.archive_outlined,
          label: tr('Archived tasks'),
          onTap: () => app.push(
            'list:archived',
            const TaskListPage(kind: ListKind.archived),
          ),
        ),
      ],
    );
  }

  // Backup --------------------------------------------------------------------------

  Widget _backup(AppSettings s) {
    final app = context.app;
    final p = context.palette;
    final now = app.store.now;
    final last = s.lastBackupAt;
    return _Group(
      title: tr('Data & Backup'),
      children: [
        _Row(
          label: tr('Daily automatic backup'),
          sub: last == null
              ? tr('No backup yet')
              : tr('Last backup {when}', {
                  'when': formatStamp(last, now, use24h: s.use24h),
                }),
          trailing: MiniSwitch(
            value: s.autoBackup,
            onChanged: (v) => _set((s) => s.autoBackup = v),
          ),
        ),
        _Row(
          label: tr('Keep'),
          enabled: s.autoBackup,
          trailing: _MenuButton<int>(
            enabled: s.autoBackup,
            value: s.backupKeep,
            options: {
              7: tr('7 backups'),
              14: tr('14 backups'),
              30: tr('30 backups'),
              90: tr('90 backups'),
            },
            onChanged: (v) {
              _set((s) => s.backupKeep = v);
              app.backups.prune().then((_) => _refresh());
            },
          ),
        ),
        _Divider(),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              DButton(
                label: tr('Back up now'),
                icon: Icons.backup_outlined,
                dense: true,
                onTap: () async {
                  await app.backups.backupNow(reason: 'manual');
                  app.toasts.show(tr('Backup saved'));
                  _refresh();
                },
              ),
              DButton(
                label: tr('Export…'),
                icon: Icons.ios_share_rounded,
                dense: true,
                onTap: _export,
              ),
              DButton(
                label: tr('Import…'),
                icon: Icons.file_download_outlined,
                dense: true,
                onTap: _import,
              ),
              Builder(
                builder: (context) => DButton(
                  label: tr('Restore…'),
                  icon: Icons.history_rounded,
                  dense: true,
                  onTap: _backups.isEmpty ? null : () => _restore(context),
                ),
              ),
              DButton(
                label: tr('Show in Finder'),
                icon: Icons.folder_open_outlined,
                dense: true,
                onTap: () async {
                  await app.backups.directory.create(recursive: true);
                  final latest = _backups.isEmpty
                      ? null
                      : _backups.first.file.path;
                  await app.native.revealInFinder(
                    latest ?? app.backups.directory.path,
                  );
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 10),
          child: Text(
            tr(
              'Everything is stored on this Mac in a local database and saved the moment you change it. Import merges a backup into your tasks; Restore replaces them (a safety copy is made first).',
            ),
            style: Type.caption.copyWith(color: p.textTertiary),
          ),
        ),
      ],
    );
  }

  Future<void> _export() async {
    final app = context.app;
    final path = await app.native.saveFile(
      'Docket Backup ${ymd(app.store.now)}.json',
    );
    if (path == null) return;
    try {
      await app.backups.exportTo(path);
      app.toasts.show(
        tr('Exported {n} tasks', {'n': app.store.allTasks.length}),
      );
    } catch (e) {
      app.toasts.show(tr('Export failed: {error}', {'error': e}));
    }
  }

  Future<void> _import() async {
    final app = context.app;
    final path = await app.native.openFile();
    if (path == null) return;
    try {
      final r = await app.backups.importFrom(path);
      app.toasts.show(
        r.added + r.updated == 0
            ? tr('Nothing new to import')
            : tr('Imported: {added} new, {updated} updated', {
                'added': r.added,
                'updated': r.updated,
              }),
      );
      _refresh();
    } on BackupFormatException catch (e) {
      app.toasts.show(e.message);
    } catch (e) {
      app.toasts.show(tr('Import failed: {error}', {'error': e}));
    }
  }

  Future<void> _restore(BuildContext anchorContext) async {
    final app = context.app;
    final now = app.store.now;
    final file = await showDocketMenu<BackupFile>(
      anchorContext,
      anchor: globalRect(anchorContext),
      width: 260,
      items: [
        MenuHeader(tr('Restore from')),
        for (final b in _backups.take(20))
          MenuItemX(
            label:
                '${formatStamp(b.createdAt, now, use24h: app.store.settings.use24h)}'
                '${b.file.path.contains('-before-') ? '  ${tr('(safety copy)')}' : ''}',
            value: b,
            icon: Icons.history_rounded,
          ),
      ],
    );
    if (file == null || !mounted) return;
    final ok = await confirmDialog(
      context,
      title: tr('Restore this backup?'),
      message: tr(
        'Your current tasks will be replaced by the backup from {when}. A safety copy of the current data is saved first.',
        {'when': formatStamp(file.createdAt, now)},
      ),
      confirmLabel: tr('Restore'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await app.backups.restore(file.file);
      app.settingsChanged(display: true);
      app.toasts.show(tr('Restored'));
      _refresh();
    } catch (e) {
      app.toasts.show(tr('Restore failed: {error}', {'error': e}));
    }
  }

  // General -----------------------------------------------------------------------

  Widget _general() {
    final app = context.app;
    final p = context.palette;
    final unsupported = _loginStatus == 'unsupported';
    return _Group(
      title: tr('General'),
      children: [
        _Row(
          label: tr('Open at login'),
          sub: _loginStatus == 'requiresApproval'
              ? tr('Approve Docket in System Settings › General › Login Items')
              : unsupported
              ? tr('Requires macOS 13 or later')
              : tr('Keeps Docket in your menu bar after a restart'),
          trailing: MiniSwitch(
            value:
                _loginStatus == 'enabled' || _loginStatus == 'requiresApproval',
            onChanged: unsupported
                ? null
                : (v) async {
                    final r = await app.native.setLaunchAtLogin(v);
                    setState(() => _loginStatus = r);
                  },
          ),
        ),
        _Divider(),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 10),
          child: Row(
            children: [
              Text(
                'Docket ${_info['version'] ?? ''}${(_info['build'] ?? '').isEmpty ? '' : ' (${_info['build']})'}',
                style: Type.caption.copyWith(color: p.textTertiary),
              ),
              const Spacer(),
              DButton(
                label: tr('Quit Docket'),
                dense: true,
                kind: ButtonKind.danger,
                hint: '⌘Q',
                onTap: app.quit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Building blocks -------------------------------------------------------------------

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(6, 16, 6, 6),
          child: Text(
            title,
            style: Type.section.copyWith(color: p.textSecondary),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    this.sub,
    this.trailing,
    this.enabled = true,
    this.subColor,
  });
  final String label;
  final String? sub;
  final Widget? trailing;
  final bool enabled;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasSub = sub != null && sub!.isNotEmpty;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          10,
          hasSub ? 8 : 6,
          8,
          hasSub ? 8 : 6,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 26),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: Type.body.copyWith(color: p.text)),
                    if (hasSub) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub!,
                        style: Type.caption.copyWith(
                          color: subColor ?? p.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: context.palette.divider,
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: hovered ? p.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: p.accent),
            const SizedBox(width: 8),
            Text(label, style: Type.body.copyWith(color: p.accent)),
          ],
        ),
      ),
    );
  }
}

class _MenuButton<T> extends StatelessWidget {
  const _MenuButton({
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => FieldButton(
        label: options[value] ?? '$value',
        trailingChevron: true,
        onTap: !enabled
            ? null
            : () async {
                final v = await showDocketMenu<T>(
                  context,
                  anchor: globalRect(context),
                  width: 190,
                  items: [
                    for (final e in options.entries)
                      MenuItemX(
                        label: e.value,
                        value: e.key,
                        checked: e.key == value,
                      ),
                  ],
                );
                if (v != null) onChanged(v);
              },
      ),
    );
  }
}

class _KeyLegend extends StatelessWidget {
  const _KeyLegend(this.keys, this.label);
  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: 98,
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              keys,
              textDirection: TextDirection.ltr,
              textAlign: Directionality.of(context) == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
              style: Type.small.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Type.caption.copyWith(color: p.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Click, then press the new combination. Esc cancels; ⌫ restores the default.
class _ShortcutRecorder extends StatefulWidget {
  const _ShortcutRecorder({
    required this.value,
    required this.onChanged,
    required this.fallback,
    required this.other,
    this.enabled = true,
  });

  final HotKey value;
  final ValueChanged<HotKey> onChanged;
  final HotKey fallback;
  final HotKey other;
  final bool enabled;

  @override
  State<_ShortcutRecorder> createState() => _ShortcutRecorderState();
}

class _ShortcutRecorderState extends State<_ShortcutRecorder> {
  final _focus = FocusNode();
  bool _recording = false;
  String? _error;
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _recording) _stop();
    });
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _recording = true;
      _error = null;
    });
    context.app.hotkeys.suspend();
    _focus.requestFocus();
  }

  void _stop() {
    setState(() => _recording = false);
    context.app.hotkeys.apply();
  }

  void _showError(String message) {
    _errorTimer?.cancel();
    setState(() => _error = message);
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _error = null);
    });
  }

  Future<KeyEventResult> _handle(KeyEvent event) async {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _stop();
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      widget.onChanged(widget.fallback);
      _stop();
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    if (isModifierKey(event.physicalKey)) return KeyEventResult.handled;
    final hotKey = hotKeyFromEvent(event);
    if (hotKey == null) {
      _showError(tr('Include ⌘, ⌃ or ⌥'));
      return KeyEventResult.handled;
    }
    if (hotKey == widget.other) {
      _showError(tr('Already used for the other shortcut'));
      return KeyEventResult.handled;
    }
    final conflict = await context.app.native.checkHotKey(
      hotKey.keyCode,
      hotKey.modifiers,
    );
    if (!mounted) return KeyEventResult.handled;
    if (conflict == 'system') {
      _showError(tr('{key} is a macOS shortcut', {'key': hotKey.label}));
      return KeyEventResult.handled;
    }
    widget.onChanged(hotKey);
    _stop();
    _focus.unfocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (!_recording) return KeyEventResult.ignored;
        _handle(event);
        return KeyEventResult.handled;
      },
      child: Hoverable(
        onTap: widget.enabled ? (_recording ? _stop : _start) : null,
        builder: (context, hovered, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 26,
          constraints: const BoxConstraints(minWidth: 92),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _recording
                ? p.accentSoft
                : (hovered && widget.enabled ? p.pressed : p.field),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _recording ? p.accent : Colors.transparent,
            ),
          ),
          child: Text(
            _error ?? (_recording ? tr('Press keys…') : widget.value.label),
            textDirection: _error == null && !_recording
                ? TextDirection.ltr
                : null,
            style: Type.small.copyWith(
              color: _error != null
                  ? p.urgent
                  : (_recording ? p.accent : p.text),
              fontWeight: _recording || _error != null
                  ? FontWeight.w500
                  : FontWeight.w600,
              letterSpacing: _recording ? 0 : 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Four display modes as cards with a short description of the chosen one.
class _DisplayModePicker extends StatelessWidget {
  const _DisplayModePicker({required this.value, required this.onChanged});
  final DisplayMode value;
  final ValueChanged<DisplayMode> onChanged;

  static String describe(DisplayMode m) => switch (m) {
    DisplayMode.small => tr(
      'A small drop-down with the summary and urgent tasks — for quick adds and check-ins.',
    ),
    DisplayMode.normal => tr(
      'The default drop-down: companies, today and the essentials.',
    ),
    DisplayMode.large => tr(
      'A bigger drop-down with more detail and room for lists.',
    ),
    DisplayMode.curtain => tr(
      'A full-width glass curtain that drops from the top of the screen, with everything in columns.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Display mode'), style: Type.body.copyWith(color: p.text)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final m in DisplayMode.values) ...[
                if (m != DisplayMode.small) const SizedBox(width: 6),
                Expanded(
                  child: _ModeCard(
                    mode: m,
                    selected: m == value,
                    onTap: () => onChanged(m),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            describe(value),
            style: Type.caption.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final DisplayMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accent : p.textTertiary;
    // A tiny picture of the screen: menu bar strip plus the window's footprint.
    Widget preview() {
      final (double w, double h, AlignmentGeometry a) = switch (mode) {
        DisplayMode.small => (0.26, 0.42, AlignmentDirectional.topEnd),
        DisplayMode.normal => (0.32, 0.6, AlignmentDirectional.topEnd),
        DisplayMode.large => (0.42, 0.78, AlignmentDirectional.topEnd),
        DisplayMode.curtain => (1.0, 0.72, Alignment.topCenter),
      };
      return Container(
        height: 40,
        decoration: BoxDecoration(
          color: p.field,
          borderRadius: BorderRadius.circular(5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(height: 4, color: color.withValues(alpha: 0.25)),
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  end: mode.isCurtain ? 0 : 5,
                ),
                child: FractionallySizedBox(
                  widthFactor: w,
                  heightFactor: h,
                  alignment: a,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withValues(
                        alpha: mode.isCurtain ? 0.35 : 0.6,
                      ),
                      borderRadius: mode.isCurtain
                          ? const BorderRadius.vertical(
                              bottom: Radius.circular(4),
                            )
                          : BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected
              ? p.accentSoft
              : (hovered ? p.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? p.accent : p.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            preview(),
            const SizedBox(height: 6),
            Text(
              mode.label,
              style: Type.small.copyWith(
                color: selected ? p.accent : p.text,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.display,
    required this.onChanged,
    required this.onChangeEnd,
    this.min = 0,
    this.max = 1,
  });

  final String label;
  final double value;
  final String display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 2, 8, 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Type.body.copyWith(color: p.text)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: p.accent,
                inactiveTrackColor: p.field,
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                  elevation: 2,
                ),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              display,
              textAlign: TextAlign.end,
              style: Type.small.copyWith(
                color: p.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/settings.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/quick_add_bar.dart';
import '../widgets/task_row.dart';
import '../../l10n/l10n.dart';

/// The panel's root: date, a one-line overview, companies, and today's tasks.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scroll = ScrollController();
  AppController? _app;

  static const todayLimit = 7;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= context.app..homeReset.addListener(_scrollToTop);
  }

  void _scrollToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _app?.homeReset.removeListener(_scrollToTop);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    return Material(
      type: MaterialType.transparency,
      child: StoreBuilder(
        builder: (context) {
          final store = app.store;
          final settings = store.settings;
          final now = store.now;
          final summary = store.summary();
          final counts = store.countsByCompany();
          final today = store.todayTasks();
          // Small: summary + urgent only. Large: more rows, descriptions, In Progress.
          final mode = settings.displayMode;
          final small = mode == DisplayMode.small;
          final large = mode == DisplayMode.large;
          final todayLimit = large ? 12 : _HomePageState.todayLimit;
          final urgent = small
              ? store.listTasks(ListKind.urgent, sort: settings.sortMode)
              : const <Task>[];
          final doing = large
              ? store.listTasks(ListKind.inProgress, sort: settings.sortMode)
              : const <Task>[];
          // Finished today stays visible, ticked, under the open tasks.
          final keepDone = settings.showCompletedInLists;
          final doneToday = keepDone && !small && settings.showToday
              ? store.completedFor(ListKind.today)
              : const <Task>[];
          final doneUrgent = keepDone && small
              ? store.completedFor(ListKind.urgent)
              : const <Task>[];
          Widget doneRow(Task t) => TaskRow(
            key: ValueKey('d-${t.id}'),
            task: t,
            showCompany: true,
            showDescription: false,
          );
          app.contextCompanyId = null;

          return Column(
            children: [
              _Header(),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        2,
                        16,
                        0,
                      ),
                      child: Text(
                        formatLongDate(now),
                        style: Type.largeTitle.copyWith(color: p.text),
                      ),
                    ),
                    if (settings.showSummary) ...[
                      const SizedBox(height: 10),
                      _SummaryRow(summary: summary),
                    ],
                    if (!settings.welcomeDismissed) const _WelcomeCard(),
                    if (small) ...[
                      SectionHeader(
                        tr('Urgent'),
                        count: urgent.isEmpty ? null : urgent.length,
                        trailing: LinkButton(
                          tr('Show all'),
                          icon: Icons.chevron_right_rounded,
                          onTap: () => app.openList(ListKind.urgent),
                        ),
                      ),
                      if (urgent.isEmpty)
                        _AllClear(
                          hasTasks: summary.open > 0,
                          message: tr('No urgent tasks'),
                        )
                      else
                        for (final t in urgent.take(6))
                          TaskRow(
                            key: ValueKey(t.id),
                            task: t,
                            showCompany: true,
                            showDescription: false,
                          ),
                      ...completedTail(
                        doneUrgent,
                        row: doneRow,
                        limit: 3,
                        onShowAll: () => app.openList(ListKind.urgent),
                      ),
                    ],
                    if (settings.showCompanies && !small) ...[
                      SectionHeader(
                        tr('Companies'),
                        trailing: LinkButton(
                          tr('Edit'),
                          onTap: app.openSettings,
                        ),
                      ),
                      for (final c in store.companies)
                        _CompanyRow(
                          company: c,
                          counts: counts[c.id] ?? CompanyCounts(),
                        ),
                    ],
                    if (settings.showToday && !small) ...[
                      SectionHeader(
                        tr('Today'),
                        count: today.isEmpty ? null : today.length,
                        trailing: LinkButton(
                          tr('Show all'),
                          icon: Icons.chevron_right_rounded,
                          onTap: () => app.openList(ListKind.today),
                        ),
                      ),
                      if (today.isEmpty)
                        _AllClear(hasTasks: summary.open > 0)
                      else ...[
                        for (final t in today.take(todayLimit))
                          TaskRow(
                            key: ValueKey(t.id),
                            task: t,
                            showCompany: true,
                            showDescription: large,
                          ),
                        if (today.length > todayLimit)
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              40,
                              4,
                              16,
                              0,
                            ),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: LinkButton(
                                tr('{n} more for today', {
                                  'n': today.length - todayLimit,
                                }),
                                onTap: () => app.openList(ListKind.today),
                              ),
                            ),
                          ),
                      ],
                      ...completedTail(
                        doneToday,
                        row: doneRow,
                        limit: large ? 8 : 5,
                        onShowAll: () => app.openList(ListKind.today),
                      ),
                    ],
                    if (large && doing.isNotEmpty) ...[
                      SectionHeader(
                        tr('In Progress'),
                        count: doing.length,
                        trailing: LinkButton(
                          tr('Show all'),
                          icon: Icons.chevron_right_rounded,
                          onTap: () => app.openList(ListKind.inProgress),
                        ),
                      ),
                      for (final t in doing.take(8))
                        TaskRow(
                          key: ValueKey('p-${t.id}'),
                          task: t,
                          showCompany: true,
                        ),
                    ],
                  ],
                ),
              ),
              Container(height: 1, color: p.divider),
              const QuickAddBar(),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 10, 0),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.checklist_rounded, size: 14, color: p.onAccent),
            ),
            const SizedBox(width: 8),
            Text(
              'Docket',
              style: Type.bodyStrong.copyWith(
                color: p.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            DIconButton(
              icon: Icons.search_rounded,
              tooltip: tr('Search  ⌘F'),
              onTap: app.openSearch,
            ),
            DIconButton(
              icon: Icons.add_rounded,
              iconSize: 19,
              tooltip: tr('New task  ⌘N'),
              onTap: () => app.newTask(),
            ),
            DIconButton(
              icon: Icons.tune_rounded,
              tooltip: tr('Settings  ⌘,'),
              onTap: app.openSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});
  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _Stat(
            value: summary.open,
            label: tr('stat|Open'),
            onTap: () => app.openList(ListKind.all),
          ),
          _Stat(
            value: summary.urgent,
            label: tr('Urgent'),
            color: summary.urgent > 0 ? p.urgent : null,
            onTap: () => app.openList(ListKind.urgent),
          ),
          _Stat(
            value: summary.inProgress,
            label: tr('In Progress'),
            onTap: () => app.openList(ListKind.inProgress),
          ),
          _Stat(
            value: summary.overdue,
            label: tr('Overdue'),
            color: summary.overdue > 0 ? p.warning : null,
            onTap: () => app.openList(ListKind.overdue),
          ),
          _Stat(
            value: summary.completed,
            label: tr('stat|Done'),
            onTap: () => app.openList(ListKind.completed),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.onTap,
    this.color,
  });
  final int value;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered, pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsetsDirectional.fromSTEB(8, 7, 4, 7),
          decoration: BoxDecoration(
            color: pressed
                ? p.pressed
                : hovered
                ? p.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: Type.number.copyWith(
                  color: value == 0 ? p.textTertiary : (color ?? p.text),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyRow extends StatelessWidget {
  const _CompanyRow({required this.company, required this.counts});
  final Company company;
  final CompanyCounts counts;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    final parts = [
      tr('{n} to do', {'n': counts.todo}),
      if (counts.inProgress > 0)
        tr('{n} in progress', {'n': counts.inProgress}),
      tr('{n} done', {'n': counts.done}),
    ];
    return Hoverable(
      onTap: () => app.openCompany(company),
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 8, 7),
        decoration: BoxDecoration(
          color: pressed
              ? p.pressed
              : hovered
              ? p.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            CompanyAvatar(company: company, size: 28),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoText(
                    company.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.bodyStrong.copyWith(color: p.text),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    parts.join(' · '),
                    style: Type.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            if (counts.overdue > 0) ...[
              _CountBadge(
                count: counts.overdue,
                color: p.warning,
                tooltip: tr('Overdue'),
              ),
              const SizedBox(width: 4),
            ],
            if (counts.urgent > 0) ...[
              _CountBadge(
                count: counts.urgent,
                color: p.urgent,
                tooltip: tr('Urgent'),
                icon: Icons.flag_rounded,
              ),
              const SizedBox(width: 4),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: hovered ? p.textSecondary : p.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.count,
    required this.color,
    required this.tooltip,
    this.icon,
  });
  final int count;
  final Color color;
  final String tooltip;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.palette.isDark ? 0.2 : 0.11),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.schedule_rounded, size: 10, color: color),
            const SizedBox(width: 2),
            Text('$count', style: Type.captionStrong.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear({required this.hasTasks, this.message});
  final bool hasTasks;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: p.divider),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined, size: 17, color: p.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message ??
                    (hasTasks
                        ? tr('Nothing due today.')
                        : tr('No tasks yet — add one below.')),
                style: Type.small.copyWith(color: p.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    final s = app.store.settings;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 0),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: p.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Make it yours'),
                    style: Type.bodyStrong.copyWith(color: p.text),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tr(
                      'Rename the three companies and pick their colours. Press {quickAdd} anywhere to add a task, {toggle} to open Docket.',
                      {
                        'quickAdd': s.quickAddHotKey.label,
                        'toggle': s.toggleHotKey.label,
                      },
                    ),
                    style: Type.small.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: 9),
                  DButton(
                    label: tr('Set up companies'),
                    dense: true,
                    kind: ButtonKind.primary,
                    onTap: app.openSettings,
                  ),
                ],
              ),
            ),
            DIconButton(
              icon: Icons.close_rounded,
              size: 22,
              iconSize: 14,
              tooltip: tr('Dismiss'),
              onTap: () =>
                  app.store.updateSettings((s) => s.welcomeDismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}

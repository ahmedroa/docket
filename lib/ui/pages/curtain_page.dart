import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../l10n/l10n.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/quick_add_bar.dart';
import '../widgets/session_list.dart';
import '../widgets/task_row.dart';
import 'task_editor_page.dart';

/// Curtain mode: a full-width glass sheet with everything on one screen —
/// summary and search on top, navigation on the side, tasks in columns, and
/// the selected task in a pane on the end side.
class CurtainHome extends StatelessWidget {
  const CurtainHome({super.key});

  /// Narrower curtains leave the session list out to keep room for columns.
  static const sessionMinWidth = 1100.0;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: Listenable.merge([app.store, app.curtain]),
        builder: (context, _) {
          final c = app.curtain;
          app.contextCompanyId = c.view == CurtainView.company
              ? c.companyId
              : null;
          final task = app.store.task(c.taskId);
          final width = MediaQuery.sizeOf(context).width;
          final showSession =
              app.store.settings.curtainShowSession &&
              width >= CurtainHome.sessionMinWidth;
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(22, 16, 22, 30),
            child: Column(
              children: [
                const _TopBar(),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (width >= 900) ...[
                        const SizedBox(width: 216, child: _Sidebar()),
                        const SizedBox(width: 14),
                      ],
                      const Expanded(child: _Main()),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: task == null
                            ? const SizedBox(width: 0)
                            : Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 14,
                                ),
                                child: SizedBox(
                                  width: math.min(420, width * 0.4),
                                  child: _DetailPane(task: task),
                                ),
                              ),
                      ),
                      // The session list sits on the end edge (left in Arabic).
                      if (showSession) ...[
                        const SizedBox(width: 14),
                        const SizedBox(
                          width: 270,
                          child: _Glass(child: SessionList()),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Rebuilds on data or curtain changes. The sections are const widgets, so
/// they must listen themselves rather than rely on the parent rebuilding.
class _Live extends StatelessWidget {
  const _Live({required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.store, app.curtain]),
      builder: (context, _) => builder(context),
    );
  }
}

/// Translucent card used for the sidebar and columns.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.padding, this.highlight = false});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: padding,
      decoration: BoxDecoration(
        color: highlight
            ? Color.alphaBlend(p.accentSoft, p.surface)
            : p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? p.accent.withValues(alpha: 0.6) : p.border,
        ),
      ),
      child: child,
    );
  }
}

// -----------------------------------------------------------------------------
// Top bar
// -----------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return _Live(
      builder: (context) {
        final p = context.palette;
        final app = context.app;
        final store = app.store;
        final c = app.curtain;
        final s = store.summary();
        // Narrow windows (e.g. the moment before macOS widens the curtain)
        // drop the pills and let search shrink instead of overflowing.
        final wide = MediaQuery.sizeOf(context).width >= 1100;
        return SizedBox(
          height: 54,
          child: Row(
            children: [
              Flexible(
                flex: wide ? 0 : 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatLongDate(store.now),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.largeTitle.copyWith(
                        fontSize: 23,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.checklist_rounded,
                          size: 13,
                          color: p.accent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Docket',
                          style: Type.captionStrong.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 26),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _StatPill(
                            value: s.urgent,
                            label: tr('Urgent'),
                            color: p.urgent,
                            icon: Icons.flag_rounded,
                            onTap: () => app.openList(ListKind.urgent),
                          ),
                          _StatPill(
                            value: s.overdue,
                            label: tr('Overdue'),
                            color: p.warning,
                            icon: Icons.schedule_rounded,
                            onTap: () => app.openList(ListKind.overdue),
                          ),
                          _StatPill(
                            value: s.dueToday,
                            label: tr('Today'),
                            color: p.accent,
                            icon: Icons.wb_sunny_outlined,
                            onTap: () => app.openList(ListKind.today),
                          ),
                          _StatPill(
                            value: s.open,
                            label: tr('stat|Open'),
                            icon: Icons.inbox_outlined,
                            onTap: () => app.openList(ListKind.all),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ] else
                const SizedBox(width: 16),
              _SearchSlot(
                wide: wide,
                child: DTextField(
                  controller: c.searchController,
                  focusNode: c.searchFocus,
                  filled: true,
                  hint: tr('Search tasks, notes, tags, companies…'),
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 10, 9),
                  prefix: Icon(
                    Icons.search_rounded,
                    size: 17,
                    color: p.textTertiary,
                  ),
                  suffix: c.query.isEmpty
                      ? const KeyHint('⌘F')
                      : GestureDetector(
                          onTap: () {
                            c.searchController.clear();
                            c.setQuery('');
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Icon(
                              Icons.cancel_rounded,
                              size: 15,
                              color: p.textTertiary,
                            ),
                          ),
                        ),
                  onChanged: c.setQuery,
                ),
              ),
              const SizedBox(width: 10),
              if (wide)
                DButton(
                  label: tr('New task'),
                  icon: Icons.add_rounded,
                  hint: '⌘N',
                  kind: ButtonKind.primary,
                  onTap: () => app.newTask(),
                )
              else
                DIconButton(
                  icon: Icons.add_rounded,
                  size: 32,
                  tooltip: tr('New task  ⌘N'),
                  onTap: () => app.newTask(),
                ),
              const SizedBox(width: 6),
              if (MediaQuery.sizeOf(context).width >=
                  CurtainHome.sessionMinWidth)
                DIconButton(
                  icon: Icons.bolt_rounded,
                  size: 32,
                  active: store.settings.curtainShowSession,
                  tooltip: store.settings.curtainShowSession
                      ? tr('Hide session')
                      : tr('Show session'),
                  onTap: () => store.updateSettings(
                    (s) => s.curtainShowSession = !s.curtainShowSession,
                  ),
                ),
              DIconButton(
                icon: Icons.tune_rounded,
                size: 32,
                tooltip: tr('Settings'),
                onTap: app.openSettings,
              ),
              DIconButton(
                icon: Icons.keyboard_arrow_up_rounded,
                size: 32,
                iconSize: 22,
                tooltip: tr('Close  esc'),
                onTap: app.hidePanel,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Fixed width on wide screens; takes the free space on narrow ones.
class _SearchSlot extends StatelessWidget {
  const _SearchSlot({required this.wide, required this.child});
  final bool wide;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      wide ? SizedBox(width: 320, child: child) : Expanded(child: child);
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.value,
    required this.label,
    required this.onTap,
    this.color,
    this.icon,
  });
  final int value;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = value > 0 && color != null;
    final fg = active ? color! : p.textSecondary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active
                ? color!.withValues(alpha: hovered ? 0.24 : 0.15)
                : (hovered ? p.pressed : p.field),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                '$value',
                style: Type.title.copyWith(
                  color: active ? fg : p.text,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: Type.small.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sidebar
// -----------------------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    return _Live(
      builder: (context) {
        final p = context.palette;
        final app = context.app;
        final store = app.store;
        final c = app.curtain;
        final s = store.summary();
        final counts = store.countsByCompany();
        final todayCount = store.todayTasks().length;
        bool listSelected(ListKind k) =>
            c.view == CurtainView.list && c.list == k;

        return _Glass(
          padding: const EdgeInsets.all(8),
          child: ListView(
            children: [
              _NavItem(
                icon: Icons.dashboard_outlined,
                label: tr('Overview'),
                count: s.open,
                selected: c.view == CurtainView.overview,
                onTap: c.showOverview,
              ),
              _NavItem(
                icon: Icons.wb_sunny_outlined,
                label: tr('Today'),
                count: todayCount,
                selected: listSelected(ListKind.today),
                onTap: () => c.showList(ListKind.today),
              ),
              _NavItem(
                icon: Icons.flag_outlined,
                label: tr('Urgent'),
                count: s.urgent,
                countColor: s.urgent > 0 ? p.urgent : null,
                selected: listSelected(ListKind.urgent),
                onTap: () => c.showList(ListKind.urgent),
              ),
              _NavItem(
                icon: Icons.schedule_rounded,
                label: tr('Overdue'),
                count: s.overdue,
                countColor: s.overdue > 0 ? p.warning : null,
                selected: listSelected(ListKind.overdue),
                onTap: () => c.showList(ListKind.overdue),
              ),
              _NavItem(
                icon: Icons.timelapse_rounded,
                label: tr('In Progress'),
                count: s.inProgress,
                selected: listSelected(ListKind.inProgress),
                onTap: () => c.showList(ListKind.inProgress),
              ),
              _NavItem(
                icon: Icons.task_alt_rounded,
                label: tr('Completed'),
                count: s.completed,
                selected: listSelected(ListKind.completed),
                onTap: () => c.showList(ListKind.completed),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 16, 10, 6),
                child: Text(
                  tr('Companies'),
                  style: Type.section.copyWith(color: p.textSecondary),
                ),
              ),
              for (final company in store.companies)
                _NavItem(
                  leading: CompanyAvatar(company: company, size: 20),
                  label: company.name,
                  count: counts[company.id]?.open ?? 0,
                  selected:
                      c.view == CurtainView.company &&
                      c.companyId == company.id,
                  onTap: () => c.showCompany(company.id),
                ),
              _NavItem(
                icon: Icons.add_rounded,
                label: tr('Add company'),
                accent: true,
                onTap: () => app.editCompany(null),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.count,
    this.countColor,
    this.selected = false,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final int? count;
  final Color? countColor;
  final bool selected;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 34,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? p.accentSoft
              : pressed
              ? p.pressed
              : hovered
              ? p.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            leading ??
                Icon(
                  icon,
                  size: 17,
                  color: selected || accent ? p.accent : p.textSecondary,
                ),
            const SizedBox(width: 10),
            Expanded(
              child: AutoText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.body.copyWith(
                  color: accent ? p.accent : p.text,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (count != null && count! > 0)
              Text(
                '$count',
                style: Type.small.copyWith(
                  color: countColor ?? (selected ? p.accent : p.textTertiary),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Main area
// -----------------------------------------------------------------------------

class _Main extends StatelessWidget {
  const _Main();

  @override
  Widget build(BuildContext context) {
    return _Live(
      builder: (context) {
        final app = context.app;
        final store = app.store;
        final c = app.curtain;
        final sort = store.settings.sortMode;
        final keepCompleted = store.settings.showCompletedInLists;

        Widget content;
        if (c.query.trim().isNotEmpty) {
          final results = store.search(c.query, TaskFilter());
          content = _ColumnsSection(
            key: const ValueKey('search'),
            title: results.length == 1
                ? tr('1 result')
                : tr('{n} results', {'n': results.length}),
            tasksFor: (company) => results
                .where((t) => t.companyId == company.id && !t.isDone)
                .toList(),
            completedFor: (company) => results
                .where((t) => t.companyId == company.id && t.isDone)
                .toList(),
            emptyText: tr('No matching tasks'),
          );
        } else {
          switch (c.view) {
            case CurtainView.company:
              final company = store.company(c.companyId);
              content = company == null
                  ? const SizedBox.shrink()
                  : _Board(
                      key: ValueKey('board-${company.id}'),
                      company: company,
                    );
            case CurtainView.list:
              final kind = c.list;
              final tasks = store.listTasks(kind, sort: sort);
              final done = keepCompleted && kind != ListKind.completed
                  ? store.completedFor(kind)
                  : const <Task>[];
              content = _ColumnsSection(
                key: ValueKey('list-${kind.name}'),
                title: kind.title,
                tasksFor: (company) =>
                    tasks.where((t) => t.companyId == company.id).toList(),
                completedFor: (company) =>
                    done.where((t) => t.companyId == company.id).toList(),
                footerFor: switch (kind) {
                  ListKind.today => (company) => QuickAddBar(
                    companyId: company.id,
                    dueToday: true,
                  ),
                  ListKind.inProgress => (company) => QuickAddBar(
                    companyId: company.id,
                    status: TaskStatus.inProgress,
                  ),
                  _ => null,
                },
                emptyText: tr('Nothing here'),
              );
            case CurtainView.overview:
              content = _ColumnsSection(
                key: const ValueKey('overview'),
                title: tr('Overview'),
                grouped: true,
                tasksFor: (company) => [
                  ...store.tasksForCompany(
                    company.id,
                    TaskStatus.inProgress,
                    sort,
                  ),
                  ...store.tasksForCompany(company.id, TaskStatus.todo, sort),
                ],
                completedFor: keepCompleted
                    ? (company) => store.completedForCompany(company.id)
                    : null,
                onShowAllCompleted: (company) => c.showCompany(company.id),
                footerFor: (company) => QuickAddBar(companyId: company.id),
                emptyText: tr('Nothing to do here'),
              );
          }
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: content,
        );
      },
    );
  }
}

/// One column per company — the overview, smart lists and search results.
/// Dropping a task on another company's column moves it there.
class _ColumnsSection extends StatelessWidget {
  const _ColumnsSection({
    super.key,
    required this.title,
    required this.tasksFor,
    required this.emptyText,
    this.completedFor,
    this.onShowAllCompleted,
    this.footerFor,
    this.grouped = false,
  });

  final String title;
  final List<Task> Function(Company company) tasksFor;

  /// Completed tasks kept, ticked, at the bottom of each column (newest first).
  final List<Task> Function(Company company)? completedFor;

  /// When set, a column shows the newest [completedTailLimit] completed tasks
  /// and links here for the rest; otherwise it shows them all.
  final void Function(Company company)? onShowAllCompleted;
  final Widget Function(Company company)? footerFor;
  final String emptyText;

  /// Splits each column into In Progress and To Do.
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final store = app.store;
    final counts = store.countsByCompany();
    final companies = store.companies;
    return _ColumnsLayout(
      title: title,
      columns: [
        for (final company in companies)
          _TaskColumn(
            header: _CompanyHeader(
              company: company,
              counts: counts[company.id] ?? CompanyCounts(),
            ),
            tasks: tasksFor(company),
            completed: completedFor?.call(company) ?? const [],
            onShowAllCompleted: onShowAllCompleted == null
                ? null
                : () => onShowAllCompleted!(company),
            grouped: grouped,
            emptyText: emptyText,
            footer: footerFor?.call(company),
            showCompany: false,
            onDrop: (task) {
              if (task.companyId != company.id) app.moveTo(task, company);
            },
          ),
      ],
    );
  }
}

/// A company's To Do / In Progress / Completed side by side; drag between columns.
class _Board extends StatelessWidget {
  const _Board({super.key, required this.company});
  final Company company;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    final store = app.store;
    final sort = store.settings.sortMode;
    return _ColumnsLayout(
      titleWidget: Row(
        children: [
          CompanyAvatar(company: company, size: 26),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              company.name,
              textDirection: dirOf(context, company.name),
              overflow: TextOverflow.ellipsis,
              style: Type.title.copyWith(fontSize: 18, color: p.text),
            ),
          ),
          const SizedBox(width: 8),
          LinkButton(tr('Edit'), onTap: () => app.editCompany(company)),
        ],
      ),
      columns: [
        for (final status in TaskStatus.values)
          _TaskColumn(
            header: _StatusHeader(
              status: status,
              count: store.tasksForCompany(company.id, status, sort).length,
            ),
            tasks: store.tasksForCompany(company.id, status, sort),
            emptyText: switch (status) {
              TaskStatus.todo => tr('Nothing to do here'),
              TaskStatus.inProgress => tr('Drag a task here to start it'),
              TaskStatus.done => tr('Drag a task here to complete it'),
            },
            footer: status == TaskStatus.done
                ? null
                : QuickAddBar(
                    key: ValueKey('board-${company.id}-$status'),
                    companyId: company.id,
                    status: status,
                  ),
            showCompany: false,
            onDrop: (task) {
              if (task.companyId != company.id) app.moveTo(task, company);
              if (task.status != status) app.setStatus(task, status);
            },
          ),
      ],
    );
  }
}

/// Title row plus columns that share the width, or scroll sideways when narrow.
class _ColumnsLayout extends StatelessWidget {
  const _ColumnsLayout({this.title, this.titleWidget, required this.columns});
  final String? title;
  final Widget? titleWidget;
  final List<Widget> columns;

  /// Columns share the width down to this size, then scroll sideways.
  static const minColumnWidth = 205.0;
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 34,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child:
                titleWidget ??
                Text(
                  title ?? '',
                  style: Type.title.copyWith(fontSize: 18, color: p.text),
                ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final n = columns.length;
              final fits =
                  constraints.maxWidth >= n * minColumnWidth + (n - 1) * gap;
              if (fits) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < n; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      Expanded(child: columns[i]),
                    ],
                  ],
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: n,
                separatorBuilder: (_, _) => const SizedBox(width: gap),
                itemBuilder: (context, i) => SizedBox(
                  width: math.max(260, constraints.maxWidth / math.min(n, 2.4)),
                  child: columns[i],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TaskColumn extends StatelessWidget {
  const _TaskColumn({
    required this.header,
    required this.tasks,
    required this.emptyText,
    required this.onDrop,
    this.completed = const [],
    this.onShowAllCompleted,
    this.footer,
    this.grouped = false,
    this.showCompany = false,
  });

  final Widget header;
  final List<Task> tasks;
  final List<Task> completed;
  final VoidCallback? onShowAllCompleted;
  final String emptyText;
  final void Function(Task task) onDrop;
  final Widget? footer;
  final bool grouped;
  final bool showCompany;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final store = context.store;
    final children = <Widget>[];
    Widget card(Task t) =>
        _TaskCard(key: ValueKey(t.id), task: t, showCompany: showCompany);
    if (grouped) {
      final doing = tasks
          .where((t) => t.status == TaskStatus.inProgress)
          .toList();
      final todo = tasks.where((t) => t.status == TaskStatus.todo).toList();
      if (doing.isNotEmpty) {
        children.add(_GroupLabel(tr('In Progress'), doing.length));
        children.addAll(doing.map(card));
      }
      if (todo.isNotEmpty) {
        children.add(_GroupLabel(tr('To Do'), todo.length));
        children.addAll(todo.map(card));
      }
    } else {
      children.addAll(tasks.map(card));
    }
    if (completed.isNotEmpty) {
      if (children.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 10),
            child: Text(
              emptyText,
              style: Type.small.copyWith(color: p.textTertiary),
            ),
          ),
        );
      }
      final capped = onShowAllCompleted != null;
      children.add(_GroupLabel(tr('Completed'), completed.length));
      children.addAll(
        (capped ? completed.take(completedTailLimit) : completed).map(card),
      );
      if (capped && completed.length > completedTailLimit) {
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 4, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: LinkButton(
                tr('Show all {n} completed', {'n': completed.length}),
                onTap: onShowAllCompleted!,
              ),
            ),
          ),
        );
      }
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => store.task(d.data) != null,
      onAcceptWithDetails: (d) {
        final t = store.task(d.data);
        if (t != null) onDrop(t);
      },
      builder: (context, candidates, _) => _Glass(
        highlight: candidates.isNotEmpty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 6),
              child: header,
            ),
            Container(height: 1, color: p.divider),
            Expanded(
              child: children.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          emptyText,
                          textAlign: TextAlign.center,
                          style: Type.small.copyWith(color: p.textTertiary),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                      children: children,
                    ),
            ),
            if (footer != null) ...[
              Container(height: 1, color: p.divider),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, this.count);
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 4),
      child: Row(
        children: [
          Text(
            label,
            style: Type.captionStrong.copyWith(color: p.textSecondary),
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: Type.captionStrong.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _CompanyHeader extends StatelessWidget {
  const _CompanyHeader({required this.company, required this.counts});
  final Company company;
  final CompanyCounts counts;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    return Row(
      children: [
        CompanyAvatar(company: company, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AutoText(
                company.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.bodyStrong.copyWith(
                  color: p.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  tr('{n} to do', {'n': counts.todo}),
                  if (counts.inProgress > 0)
                    tr('{n} in progress', {'n': counts.inProgress}),
                  tr('{n} done', {'n': counts.done}),
                ].join(' · '),
                style: Type.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
        DIconButton(
          icon: Icons.view_column_outlined,
          size: 26,
          iconSize: 16,
          tooltip: tr('Open board'),
          onTap: () => app.curtain.showCompany(company.id),
        ),
      ],
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status, required this.count});
  final TaskStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (IconData icon, Color color) = switch (status) {
      TaskStatus.todo => (
        Icons.radio_button_unchecked_rounded,
        p.textSecondary,
      ),
      TaskStatus.inProgress => (Icons.timelapse_rounded, p.progress),
      TaskStatus.done => (Icons.check_circle_rounded, p.success),
    };
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Text(
            status.label,
            style: Type.bodyStrong.copyWith(
              color: p.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text('$count', style: Type.small.copyWith(color: p.textTertiary)),
        ],
      ),
    );
  }
}

/// A task as a draggable card.
class _TaskCard extends StatelessWidget {
  const _TaskCard({super.key, required this.task, this.showCompany = false});
  final Task task;
  final bool showCompany;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    final selected = app.curtain.taskId == task.id;
    final card = Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        // Completed cards sit back so the open ones above read first.
        color: task.isDone
            ? (p.isDark ? const Color(0x0DFFFFFF) : const Color(0x59FFFFFF))
            : (p.isDark ? const Color(0x1FFFFFFF) : const Color(0xB8FFFFFF)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? p.accent : p.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: TaskRow(task: task, showCompany: showCompany),
      ),
    );
    return Draggable<String>(
      data: task.id,
      feedback: _DragFeedback(task: task),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.accent.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: p.shadow,
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: AutoText(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Type.bodyStrong.copyWith(color: p.text),
        ),
      ),
    );
  }
}

/// The task editor beside the board; stays until closed or the task is gone.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.solid.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TaskEditorPage(
        key: ValueKey(task.id),
        taskId: task.id,
        onClose: app.curtain.closeTask,
      ),
    );
  }
}

/// Pages (settings, new task, quick add…) shown as a centred sheet over the glass.
class CurtainSheet extends StatelessWidget {
  const CurtainSheet({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: Container(
          width: math.min(480, constraints.maxWidth - 48),
          height: math.min(720, constraints.maxHeight - 40),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.solid,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: p.shadow,
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../data/queries.dart';
import '../../data/settings.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/menus.dart';
import '../widgets/quick_add_bar.dart';
import '../widgets/selection.dart';
import '../widgets/task_row.dart';
import '../../l10n/l10n.dart';

/// Cross-company lists: All Tasks, Today, Overdue, Urgent, In Progress,
/// Completed, This Week, Archived.
class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key, required this.kind, this.companyId});
  final ListKind kind;

  /// Restricts the list to one company (used for a company's archive).
  final String? companyId;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  final _selection = Selection();

  /// Lists that keep their completed tasks at the bottom.
  bool get _canShowCompleted =>
      widget.kind != ListKind.completed && widget.kind != ListKind.archived;

  bool get _groupByCompany =>
      widget.kind == ListKind.all ||
      widget.kind == ListKind.inProgress ||
      widget.kind == ListKind.archived;

  @override
  void initState() {
    super.initState();
    _selection.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    return StoreBuilder(
      builder: (context) {
        final store = app.store;
        final now = store.now;
        final showCompleted =
            _canShowCompleted && store.settings.showCompletedInLists;
        var tasks = store.listTasks(widget.kind, sort: store.settings.sortMode);
        var done = showCompleted && !_selection.active
            ? store.completedFor(widget.kind)
            : const <Task>[];
        if (widget.companyId != null) {
          tasks = tasks.where((t) => t.companyId == widget.companyId).toList();
          done = done.where((t) => t.companyId == widget.companyId).toList();
        }
        app.contextCompanyId = widget.companyId;
        final companyName = store.company(widget.companyId)?.name;

        Widget row(Task t) => TaskRow(
          key: ValueKey(t.id),
          task: t,
          showCompany: !_groupByCompany && widget.companyId == null,
          selectionMode: _selection.active,
          selected: _selection.contains(t),
          onSelect: _selection.toggle,
          onRangeSelect: (t) => _selection.range(t, tasks),
        );

        final children = <Widget>[];
        if (widget.kind == ListKind.completed) {
          DateTime? day;
          for (final t in tasks) {
            final d = dateOnly(t.completedAt ?? t.updatedAt);
            if (day == null || !sameDay(day, d)) {
              day = d;
              children.add(
                SectionHeader(
                  formatRelativeDay(d, now) == formatShortDate(d, now)
                      ? formatLongDate(d)
                      : '${formatRelativeDay(d, now)} · ${formatShortDate(d, now)}',
                ),
              );
            }
            children.add(row(t));
          }
        } else if (_groupByCompany && widget.companyId == null) {
          for (final c in store.companies) {
            final group = tasks.where((t) => t.companyId == c.id).toList();
            if (group.isEmpty) continue;
            children.add(
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 4),
                child: Row(
                  children: [
                    CompanyAvatar(company: c, size: 18),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Hoverable(
                        onTap: () => app.openCompany(c),
                        builder: (context, hovered, _) => Text(
                          c.name,
                          overflow: TextOverflow.ellipsis,
                          style: Type.section.copyWith(
                            color: p.textSecondary,
                            decoration: hovered
                                ? TextDecoration.underline
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${group.length}',
                      style: Type.section.copyWith(color: p.textTertiary),
                    ),
                  ],
                ),
              ),
            );
            children.addAll(group.map(row));
          }
        } else {
          children.addAll(tasks.map(row));
        }
        if (tasks.isEmpty && done.isNotEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.task_alt_rounded, size: 15, color: p.success),
                  const SizedBox(width: 7),
                  Text(
                    tr('All done'),
                    style: Type.small.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }
        children.addAll(
          completedTail(
            done,
            row: (t) => TaskRow(
              key: ValueKey(t.id),
              task: t,
              showCompany: widget.companyId == null,
            ),
            onShowAll: () => app.openList(ListKind.completed),
          ),
        );

        return PanelPage(
          titleWidget: Row(
            children: [
              Flexible(
                child: Text(
                  companyName == null
                      ? widget.kind.title
                      : '${widget.kind.title} · $companyName',
                  overflow: TextOverflow.ellipsis,
                  style: Type.title.copyWith(color: p.text),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '${tasks.length}',
                style: Type.title.copyWith(
                  color: p.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            if (_canShowCompleted)
              DIconButton(
                icon: showCompleted
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_outlined,
                tooltip: showCompleted
                    ? tr('Hide completed')
                    : tr('Show completed'),
                active: showCompleted,
                onTap: () => store.updateSettings(
                  (s) => s.showCompletedInLists = !showCompleted,
                ),
              ),
            if (tasks.isNotEmpty)
              DIconButton(
                icon: Icons.checklist_rtl_rounded,
                tooltip: tr('Select tasks'),
                active: _selection.active,
                onTap: () =>
                    _selection.active ? _selection.clear() : _selection.start(),
              ),
            if (widget.kind == ListKind.all ||
                widget.kind == ListKind.inProgress)
              Builder(
                builder: (context) => DIconButton(
                  icon: Icons.sort_rounded,
                  tooltip: tr('Sort'),
                  onTap: () async {
                    final m = await showDocketMenu<SortMode>(
                      context,
                      anchor: globalRect(context),
                      width: 180,
                      items: [
                        MenuHeader(tr('Sort by')),
                        for (final m in SortMode.values)
                          MenuItemX(
                            label: m.label,
                            value: m,
                            checked: store.settings.sortMode == m,
                          ),
                      ],
                    );
                    if (m != null) store.updateSettings((s) => s.sortMode = m);
                  },
                ),
              ),
          ],
          body: children.isEmpty
              ? _empty()
              : ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  children: children,
                ),
          bottom: _selection.active
              ? BatchBar(selection: _selection, visible: tasks)
              : switch (widget.kind) {
                  ListKind.today => const QuickAddBar(dueToday: true),
                  ListKind.all => const QuickAddBar(),
                  ListKind.inProgress => const QuickAddBar(
                    status: TaskStatus.inProgress,
                  ),
                  _ => null,
                },
        );
      },
    );
  }

  Widget _empty() => switch (widget.kind) {
    ListKind.today => EmptyState(
      icon: Icons.wb_sunny_outlined,
      title: tr('Nothing due today'),
      subtitle: tr('Urgent tasks and anything due or overdue shows up here.'),
    ),
    ListKind.overdue => EmptyState(
      icon: Icons.verified_outlined,
      title: tr('Nothing overdue'),
      subtitle: tr('Nice.'),
    ),
    ListKind.urgent => EmptyState(
      icon: Icons.outlined_flag_rounded,
      title: tr('No urgent tasks'),
    ),
    ListKind.inProgress => EmptyState(
      icon: Icons.timelapse_rounded,
      title: tr('Nothing in progress'),
    ),
    ListKind.completed => EmptyState(
      icon: Icons.task_alt_rounded,
      title: tr('No completed tasks yet'),
    ),
    ListKind.week => EmptyState(
      icon: Icons.date_range_rounded,
      title: tr('Nothing due this week'),
    ),
    ListKind.archived => EmptyState(
      icon: Icons.archive_outlined,
      title: tr('Archive is empty'),
      subtitle: tr('Archived tasks are hidden everywhere else but kept here.'),
    ),
    ListKind.all => EmptyState(
      icon: Icons.inbox_outlined,
      title: tr('No open tasks'),
    ),
  };
}

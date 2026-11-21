import 'package:flutter/material.dart';

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
import 'task_list_page.dart';
import '../../l10n/l10n.dart';

/// A company's workspace: To Do / In Progress / Completed.
class CompanyPage extends StatefulWidget {
  const CompanyPage({
    super.key,
    required this.companyId,
    this.initialTab = TaskStatus.todo,
  });
  final String companyId;
  final TaskStatus initialTab;

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends State<CompanyPage> {
  late TaskStatus _tab = widget.initialTab;
  final _selection = Selection();
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selection.addListener(() => setState(() {}));
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _selection.dispose();
    _query.dispose();
    super.dispose();
  }

  void _setTab(TaskStatus tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _selection.clear();
    });
  }

  Future<void> _menu(BuildContext anchorContext) async {
    final app = context.app;
    final store = app.store;
    final company = store.company(widget.companyId);
    if (company == null) return;
    final value = await showDocketMenu<Object>(
      anchorContext,
      anchor: globalRect(anchorContext),
      width: 220,
      items: [
        MenuItemX(
          label: tr('Edit company…'),
          value: 'edit',
          icon: Icons.edit_outlined,
        ),
        MenuItemX(
          label: tr('Select tasks'),
          value: 'select',
          icon: Icons.checklist_rtl_rounded,
        ),
        MenuItemX(
          label: tr('Archived tasks'),
          value: 'archived',
          icon: Icons.archive_outlined,
        ),
        const MenuDivider(),
        MenuHeader(tr('Sort by')),
        for (final m in SortMode.values)
          MenuItemX(
            label: m.label,
            value: m,
            checked: store.settings.sortMode == m,
          ),
      ],
    );
    if (!mounted || value == null) return;
    switch (value) {
      case 'edit':
        app.editCompany(company);
      case 'select':
        _selection.start();
      case 'archived':
        app.push(
          'archived:${company.id}',
          TaskListPage(kind: ListKind.archived, companyId: company.id),
        );
      case SortMode m:
        store.updateSettings((s) => s.sortMode = m);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    return StoreBuilder(
      builder: (context) {
        final store = app.store;
        final company = store.company(widget.companyId);
        if (company == null) {
          return PanelPage(
            title: tr('Company removed'),
            body: EmptyState(
              icon: Icons.domain_disabled_outlined,
              title: tr('This company was deleted'),
            ),
          );
        }
        app.contextCompanyId = company.id;
        final sort = store.settings.sortMode;
        final counts = store.countsByCompany()[company.id] ?? CompanyCounts();
        var tasks = store.tasksForCompany(company.id, _tab, sort);
        if (_tab == TaskStatus.done && _query.text.trim().isNotEmpty) {
          final q = normalizeForSearch(_query.text.trim());
          final now = store.now;
          tasks = tasks
              .where((t) => store.searchText(t, company, now).contains(q))
              .toList();
        }
        final reorderable =
            sort == SortMode.manual &&
            _tab != TaskStatus.done &&
            !_selection.active;

        Widget row(Task t, int i) => TaskRow(
          key: ValueKey(t.id),
          task: t,
          showAdded: true,
          reorderIndex: reorderable ? i : null,
          selectionMode: _selection.active,
          selected: _selection.contains(t),
          onSelect: _selection.toggle,
          onRangeSelect: (t) => _selection.range(t, tasks),
        );

        // Completed tasks stay at the bottom of To Do (and of In Progress for
        // the ones that were started), ticked and crossed out.
        final done =
            store.settings.showCompletedInLists &&
                _tab != TaskStatus.done &&
                !_selection.active
            ? store.completedForCompany(
                company.id,
                startedOnly: _tab == TaskStatus.inProgress,
              )
            : const <Task>[];
        // A click on a to-do's circle starts it; it moves up to this group
        // instead of leaving the To Do tab.
        final doing = _tab == TaskStatus.todo && !_selection.active
            ? store.tasksForCompany(company.id, TaskStatus.inProgress, sort)
            : const <Task>[];
        final head = [
          if (doing.isNotEmpty) ...[
            SectionHeader(tr('In Progress'), count: doing.length),
            for (final t in doing)
              TaskRow(key: ValueKey(t.id), task: t, showAdded: true),
            if (tasks.isNotEmpty)
              SectionHeader(tr('To Do'), count: tasks.length),
          ],
        ];
        final tail = [
          if (tasks.isEmpty && doing.isEmpty && done.isNotEmpty) _allDone(),
          ...completedTail(
            done,
            row: (t) => TaskRow(key: ValueKey(t.id), task: t, showAdded: true),
            onShowAll: () => _setTab(TaskStatus.done),
          ),
        ];

        Widget list;
        if (tasks.isEmpty && head.isEmpty && tail.isEmpty) {
          list = _empty(company);
        } else if (reorderable && tasks.isNotEmpty) {
          list = ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            buildDefaultDragHandles: false,
            header: head.isEmpty
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: head,
                  ),
            footer: tail.isEmpty
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: tail,
                  ),
            itemCount: tasks.length,
            onReorderItem: (o, n) => store.reorder(tasks, o, n),
            proxyDecorator: (child, index, animation) => Material(
              color: p.raised,
              elevation: 6,
              shadowColor: p.shadow,
              borderRadius: BorderRadius.circular(8),
              child: child,
            ),
            itemBuilder: (context, i) => row(tasks[i], i),
          );
        } else {
          final n = head.length + tasks.length;
          list = ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: n + tail.length,
            itemBuilder: (context, i) => i < head.length
                ? head[i]
                : i < n
                ? row(tasks[i - head.length], i - head.length)
                : tail[i - n],
          );
        }

        return PanelPage(
          titleWidget: Row(
            children: [
              CompanyAvatar(company: company, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: AutoText(
                  company.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.title.copyWith(color: p.text),
                ),
              ),
            ],
          ),
          actions: [
            DIconButton(
              icon: Icons.add_rounded,
              iconSize: 19,
              tooltip: tr('New task  ⌘N'),
              onTap: () => app.newTask(
                companyId: company.id,
                status: _tab == TaskStatus.done ? TaskStatus.todo : _tab,
              ),
            ),
            Builder(
              builder: (context) => DIconButton(
                icon: Icons.more_horiz_rounded,
                tooltip: tr('More'),
                onTap: () => _menu(context),
              ),
            ),
          ],
          headerBottom: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
            child: Segmented<TaskStatus>(
              options: TaskStatus.values,
              value: _tab,
              onChanged: _setTab,
              labels: (s, selected) {
                final n = switch (s) {
                  TaskStatus.todo => counts.todo,
                  TaskStatus.inProgress => counts.inProgress,
                  TaskStatus.done => counts.done,
                };
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      s.label,
                      style: Type.small.copyWith(
                        color: selected ? p.text : p.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$n',
                      style: Type.caption.copyWith(color: p.textTertiary),
                    ),
                  ],
                );
              },
            ),
          ),
          body: Column(
            children: [
              if (_tab == TaskStatus.done && counts.done > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 0),
                  child: DTextField(
                    controller: _query,
                    filled: true,
                    hint: tr('Search completed tasks'),
                    style: Type.small,
                    prefix: Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: p.textTertiary,
                    ),
                  ),
                ),
              Expanded(child: list),
            ],
          ),
          bottom: _selection.active
              ? BatchBar(selection: _selection, visible: tasks)
              : _tab == TaskStatus.done
              ? null
              : QuickAddBar(
                  key: ValueKey('qa-${company.id}-$_tab'),
                  companyId: company.id,
                  status: _tab,
                ),
        );
      },
    );
  }

  /// One quiet line above the completed tasks when nothing is left open.
  Widget _allDone() {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(Icons.task_alt_rounded, size: 15, color: p.success),
          const SizedBox(width: 7),
          Text(
            _tab == TaskStatus.inProgress
                ? tr('Nothing in progress')
                : tr('Nothing to do here'),
            style: Type.small.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _empty(Company company) {
    return switch (_tab) {
      TaskStatus.todo => EmptyState(
        icon: Icons.inbox_outlined,
        title: tr('Nothing to do here'),
        subtitle: tr('Add a task below — it lands at the top.'),
      ),
      TaskStatus.inProgress => EmptyState(
        icon: Icons.timelapse_rounded,
        title: tr('Nothing in progress'),
        subtitle: tr('Press ▶ on a to-do to start it.'),
      ),
      TaskStatus.done => EmptyState(
        icon: Icons.task_alt_rounded,
        title: _query.text.isEmpty
            ? tr('No completed tasks yet')
            : tr('No matches'),
      ),
    };
  }
}

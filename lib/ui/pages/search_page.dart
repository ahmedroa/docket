import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/queries.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/menus.dart';
import '../widgets/task_row.dart';
import '../../l10n/l10n.dart';

/// ⌘F — full-text search across every task with status/company/date filters.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery = ''});
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _filter = TaskFilter();
  bool _includeArchived = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggle(VoidCallback change) => setState(change);

  Future<void> _pickCompanies(BuildContext anchorContext) async {
    final store = context.store;
    final c = await showDocketMenu<String>(
      anchorContext,
      anchor: globalRect(anchorContext),
      width: 220,
      items: [
        MenuItemX(
          label: tr('All companies'),
          value: '*',
          checked: _filter.companyIds.isEmpty,
        ),
        const MenuDivider(),
        for (final c in store.companies)
          MenuItemX(
            label: c.name,
            value: c.id,
            checked: _filter.companyIds.contains(c.id),
            leading: CompanyAvatar(company: c, size: 18),
          ),
      ],
    );
    if (c == null) return;
    setState(() {
      if (c == '*') {
        _filter.companyIds.clear();
      } else if (!_filter.companyIds.remove(c)) {
        _filter.companyIds.add(c);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    return StoreBuilder(
      builder: (context) {
        final store = app.store;
        final query = _controller.text.trim();
        final searching = query.isNotEmpty || !_filter.isEmpty;
        final results = searching
            ? store.search(query, _filter, includeArchived: _includeArchived)
            : <Task>[];
        final selectedCompanies = store.companies
            .where((c) => _filter.companyIds.contains(c.id))
            .toList();

        return PanelPage(
          titleWidget: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                if (results.isNotEmpty) app.openTask(results.first);
              },
            },
            child: DTextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              filled: true,
              hint: tr('Search tasks, notes, tags, companies…'),
              prefix: Icon(
                Icons.search_rounded,
                size: 16,
                color: p.textTertiary,
              ),
              suffix: query.isEmpty
                  ? null
                  : GestureDetector(
                      onTap: () {
                        _controller.clear();
                        _focus.requestFocus();
                      },
                      child: Icon(
                        Icons.cancel_rounded,
                        size: 15,
                        color: p.textTertiary,
                      ),
                    ),
              onSubmitted: (_) {
                if (results.isNotEmpty) app.openTask(results.first);
              },
            ),
          ),
          headerBottom: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Builder(
                  builder: (context) => ChoiceChipX(
                    label: selectedCompanies.isEmpty
                        ? tr('All companies')
                        : selectedCompanies.length == 1
                        ? selectedCompanies.first.name
                        : tr('{n} companies', {'n': selectedCompanies.length}),
                    selected: selectedCompanies.isNotEmpty,
                    icon: Icons.domain_rounded,
                    onTap: () => _pickCompanies(context),
                  ),
                ),
                for (final s in TaskStatus.values)
                  ChoiceChipX(
                    label: s.label,
                    selected: _filter.statuses.contains(s),
                    onTap: () => _toggle(() {
                      if (!_filter.statuses.remove(s)) _filter.statuses.add(s);
                    }),
                  ),
                ChoiceChipX(
                  label: tr('Urgent'),
                  icon: Icons.flag_rounded,
                  color: p.urgent,
                  selected: _filter.urgent,
                  onTap: () => _toggle(() => _filter.urgent = !_filter.urgent),
                ),
                ChoiceChipX(
                  label: tr('Overdue'),
                  color: p.warning,
                  selected: _filter.overdue,
                  onTap: () =>
                      _toggle(() => _filter.overdue = !_filter.overdue),
                ),
                ChoiceChipX(
                  label: tr('Today'),
                  selected: _filter.today,
                  onTap: () => _toggle(() => _filter.today = !_filter.today),
                ),
                ChoiceChipX(
                  label: tr('This Week'),
                  selected: _filter.thisWeek,
                  onTap: () =>
                      _toggle(() => _filter.thisWeek = !_filter.thisWeek),
                ),
                ChoiceChipX(
                  label: tr('Archived'),
                  icon: Icons.archive_outlined,
                  selected: _includeArchived,
                  onTap: () =>
                      _toggle(() => _includeArchived = !_includeArchived),
                ),
              ],
            ),
          ),
          body: !searching
              ? EmptyState(
                  icon: Icons.manage_search_rounded,
                  title: tr('Search everything'),
                  subtitle: tr(
                    'Titles, descriptions, notes, subtasks, #tags, company names — or words like “urgent”, “overdue”, “tomorrow”, “nov”.',
                  ),
                )
              : results.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: tr('No matching tasks'),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        8,
                        16,
                        2,
                      ),
                      child: Row(
                        children: [
                          Text(
                            results.length == 1
                                ? tr('1 result')
                                : tr('{n} results', {'n': results.length}),
                            style: Type.caption.copyWith(color: p.textTertiary),
                          ),
                          const Spacer(),
                          if (!_filter.isEmpty)
                            LinkButton(
                              tr('Clear filters'),
                              onTap: () => setState(_filter.clear),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 10),
                        itemCount: results.length,
                        itemBuilder: (context, i) => TaskRow(
                          key: ValueKey(results[i].id),
                          task: results[i],
                          showCompany: true,
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

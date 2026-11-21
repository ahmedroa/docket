import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';
import '../widgets/quick_add_bar.dart';
import '../../l10n/l10n.dart';

/// Opened by the global Quick Add shortcut: type a title, ⇥ to change
/// company, ↵ to save. Saving returns you to the app you were in.
class QuickAddPage extends StatefulWidget {
  const QuickAddPage({super.key, this.companyId});
  final String? companyId;

  @override
  State<QuickAddPage> createState() => _QuickAddPageState();
}

enum _Due { none, today, tomorrow, custom }

class _QuickAddPageState extends State<QuickAddPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late String _companyId;
  Priority _priority = Priority.normal;
  _Due _due = _Due.none;
  DateTime? _customDue;

  @override
  void initState() {
    super.initState();
    final store = context.store;
    _companyId =
        store.company(widget.companyId)?.id ??
        store.company(QuickAddBarMemory.lastCompanyId)?.id ??
        store.companies.first.id;
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _cycleCompany(int delta) {
    final list = context.store.companies;
    final i = list.indexWhere((c) => c.id == _companyId);
    setState(() => _companyId = list[(i + delta) % list.length].id);
  }

  DateTime? get _dueDate {
    final now = context.store.now;
    return switch (_due) {
      _Due.none => null,
      _Due.today => dateOnly(now),
      _Due.tomorrow => addDays(dateOnly(now), 1),
      _Due.custom => _customDue,
    };
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final app = context.app;
    final parsed = parseQuickInput(text);
    final task = app.store.quickAdd(
      text,
      companyId: _companyId,
      due: _dueDate,
      priority: parsed.priority == Priority.urgent
          ? Priority.urgent
          : _priority,
    );
    QuickAddBarMemory.lastCompanyId = _companyId;
    final company = app.store.company(_companyId);
    if (app.quickAddFromHotkey) {
      app.hidePanel();
    } else {
      Navigator.of(context).maybePop();
      app.toasts.show(
        tr('Added to {company}', {'company': company?.name}),
        actionLabel: tr('Open'),
        onAction: () => app.openTask(task),
      );
    }
  }

  void _more() {
    final app = context.app;
    final text = _controller.text;
    app.quickAddFromHotkey = false;
    Navigator.of(context).pop();
    app.newTask(companyId: _companyId, title: text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final store = context.store;
    final companies = store.companies;
    final parsed = parseQuickInput(_controller.text);
    final urgent =
        _priority == Priority.urgent || parsed.priority == Priority.urgent;

    return PageShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.tab): () => _cycleCompany(1),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
            _cycleCompany(-1),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _more,
      },
      child: PanelPage(
        title: tr('Quick Add'),
        showBack: !context.app.quickAddFromHotkey,
        actions: [
          DIconButton(
            icon: Icons.close_rounded,
            tooltip: tr('Close  esc'),
            onTap: () => context.app.quickAddFromHotkey
                ? context.app.hidePanel()
                : Navigator.of(context).maybePop(),
          ),
        ],
        body: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _focus.hasFocus
                      ? p.accent.withValues(alpha: 0.6)
                      : p.border,
                ),
              ),
              child: Focus(
                onFocusChange: (_) => setState(() {}),
                child: DTextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 1,
                  hint: tr('What needs to be done?'),
                  style: Type.title.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _Row(
              label: tr('Company'),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in companies)
                    ChoiceChipX(
                      label: c.name,
                      selected: c.id == _companyId,
                      color: Color(c.color),
                      leading: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: Color(c.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      onTap: () {
                        setState(() => _companyId = c.id);
                        _focus.requestFocus();
                      },
                    ),
                ],
              ),
            ),
            _Row(
              label: tr('Priority'),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final pr in Priority.values)
                    ChoiceChipX(
                      label: pr.label,
                      icon: pr == Priority.urgent ? Icons.flag_rounded : null,
                      color: pr == Priority.urgent ? p.urgent : null,
                      selected: pr == Priority.urgent
                          ? urgent
                          : (!urgent && _priority == pr),
                      onTap: () {
                        setState(() => _priority = pr);
                        _focus.requestFocus();
                      },
                    ),
                ],
              ),
            ),
            _Row(
              label: tr('Due'),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in [_Due.none, _Due.today, _Due.tomorrow])
                    ChoiceChipX(
                      label: switch (d) {
                        _Due.none => tr('No date'),
                        _Due.today => tr('Today'),
                        _Due.tomorrow => tr('Tomorrow'),
                        _Due.custom => '',
                      },
                      selected: _due == d,
                      onTap: () {
                        setState(() => _due = d);
                        _focus.requestFocus();
                      },
                    ),
                  Builder(
                    builder: (context) => ChoiceChipX(
                      label: _due == _Due.custom && _customDue != null
                          ? formatShortDate(_customDue!, store.now)
                          : tr('Pick…'),
                      icon: Icons.calendar_today_rounded,
                      selected: _due == _Due.custom,
                      onTap: () async {
                        final r = await showCalendar(
                          context,
                          anchor: globalRect(context),
                          initial: _customDue,
                        );
                        if (r is DateTime) {
                          setState(() {
                            _due = _Due.custom;
                            _customDue = r;
                          });
                        }
                        _focus.requestFocus();
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (parsed.tags.isNotEmpty)
              _Row(
                label: tr('Tags'),
                child: Text(
                  parsed.tags.map((t) => '#$t').join('  '),
                  style: Type.small.copyWith(color: p.accent),
                ),
              ),
          ],
        ),
        bottom: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Hint(keys: '⇥', label: tr('company')),
                    _Hint(keys: '⌘↵', label: tr('details')),
                    _Hint(keys: '!', label: tr('urgent')),
                    _Hint(keys: '#', label: tr('tag')),
                  ],
                ),
              ),
              DButton(
                label: tr('Add'),
                hint: '↵',
                kind: ButtonKind.primary,
                onTap: _controller.text.trim().isEmpty ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                label,
                style: Type.small.copyWith(color: p.textSecondary),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.keys, required this.label});
  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyHint(keys),
        const SizedBox(width: 4),
        Text(label, style: Type.caption.copyWith(color: p.textTertiary)),
      ],
    );
  }
}

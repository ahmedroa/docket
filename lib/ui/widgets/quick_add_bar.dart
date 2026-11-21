import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../controller.dart';
import '../theme.dart';
import 'common.dart';
import 'task_row.dart';
import '../../l10n/l10n.dart';

/// The company last used for a quick add, remembered across panel openings.
class QuickAddBarMemory {
  static String? lastCompanyId;
}

/// Always-visible one-line add field at the bottom of the panel.
/// ↵ saves; "!" marks urgent, "#tag" adds a tag; ⌘↵ opens the full form.
class QuickAddBar extends StatefulWidget {
  const QuickAddBar({
    super.key,
    this.companyId,
    this.status = TaskStatus.todo,
    this.dueToday = false,
  });

  /// Fixed company (company page); otherwise a picker is shown.
  final String? companyId;
  final TaskStatus status;

  /// Tasks added from the Today list are due today.
  final bool dueToday;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Company _company() {
    final store = context.store;
    return store.company(widget.companyId) ??
        store.company(_companyId) ??
        store.company(QuickAddBarMemory.lastCompanyId) ??
        store.personal;
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final app = context.app;
    final company = _company();
    final task = app.store.quickAdd(
      text,
      companyId: company.id,
      due: widget.dueToday ? app.store.now : null,
    );
    if (widget.status != TaskStatus.todo) {
      app.store.setStatus(task, widget.status);
    }
    if (widget.companyId == null) QuickAddBarMemory.lastCompanyId = company.id;
    _controller.clear();
    _focus.requestFocus();
    app.toasts.show(
      widget.companyId == null
          ? tr('Added to {company}', {'company': company.name})
          : tr('Added'),
      actionLabel: tr('Open'),
      onAction: () => app.openTask(task),
    );
  }

  void _expand() {
    final app = context.app;
    final text = _controller.text;
    _controller.clear();
    app.newTask(companyId: _company().id, status: widget.status, title: text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final company = _company();
    final hasText = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 10),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _expand,
        },
        child: Container(
          height: 34,
          padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                Icons.add_rounded,
                size: 17,
                color: _focus.hasFocus ? p.accent : p.textTertiary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Focus(
                  onFocusChange: (_) => setState(() {}),
                  child: DTextField(
                    controller: _controller,
                    focusNode: _focus,
                    hint: widget.status == TaskStatus.inProgress
                        ? tr('Add an in-progress task…')
                        : widget.dueToday
                        ? tr('Add a task for today…')
                        : tr('Add a task…'),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              if (hasText)
                DIconButton(
                  icon: Icons.open_in_full_rounded,
                  size: 24,
                  iconSize: 13,
                  tooltip: tr('More details  ⌘↵'),
                  onTap: _expand,
                ),
              if (widget.companyId == null)
                Builder(
                  builder: (context) => Tooltip(
                    message: tr('Company'),
                    child: Hoverable(
                      onTap: () async {
                        final c = await pickCompany(
                          context,
                          anchor: globalRect(context),
                          current: company.id,
                        );
                        if (c != null) {
                          setState(() => _companyId = c.id);
                          QuickAddBarMemory.lastCompanyId = c.id;
                          _focus.requestFocus();
                        }
                      },
                      builder: (context, hovered, _) => Container(
                        height: 26,
                        constraints: const BoxConstraints(maxWidth: 130),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        decoration: BoxDecoration(
                          color: hovered ? p.hover : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: CompanyChip(company: company)),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 14,
                              color: p.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

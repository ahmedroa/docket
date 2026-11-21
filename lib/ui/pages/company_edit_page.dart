import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../../l10n/l10n.dart';

/// Create or edit a company: name, colour, icon. Edits save as you go.
class CompanyEditPage extends StatefulWidget {
  const CompanyEditPage({super.key, this.companyId});
  final String? companyId;

  @override
  State<CompanyEditPage> createState() => _CompanyEditPageState();
}

class _CompanyEditPageState extends State<CompanyEditPage> {
  final _name = TextEditingController();
  late int _color;
  late String _icon;

  bool get _isNew => widget.companyId == null;

  @override
  void initState() {
    super.initState();
    final store = context.store;
    final c = store.company(widget.companyId);
    if (c != null) {
      _name.text = c.name;
      _color = c.color;
      _icon = c.icon;
    } else {
      final used = store.companies.map((c) => c.color).toSet();
      _color = CompanyDefaults.palette.firstWhere(
        (c) => !used.contains(c),
        orElse: () => CompanyDefaults.palette.first,
      );
      _icon = 'work';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _apply({String? name, int? color, String? icon}) {
    setState(() {
      _color = color ?? _color;
      _icon = icon ?? _icon;
    });
    if (_isNew) return;
    final c = context.store.company(widget.companyId);
    if (c != null) {
      context.store.updateCompany(c, name: name, color: color, icon: icon);
    }
  }

  void _create() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final app = context.app;
    app.store.addCompany(name: name, color: _color, icon: _icon);
    Navigator.of(context).maybePop();
    app.toasts.show(tr('Added {name}', {'name': name}));
  }

  Future<void> _delete(Company c) async {
    final app = context.app;
    final count = app.store.allTasks.where((t) => t.companyId == c.id).length;
    final personal = app.store.personal;
    String? choice;
    if (count == 0) {
      final ok = await confirmDialog(
        context,
        title: tr('Delete {name}?', {'name': c.name}),
        confirmLabel: tr('Delete'),
        destructive: true,
      );
      choice = ok ? 'delete' : null;
    } else {
      choice = await choiceDialog(
        context,
        title: tr('Delete {name}?', {'name': c.name}),
        message: count == 1
            ? tr('It has 1 task.')
            : tr('It has {n} tasks.', {'n': count}),
        choices: [
          (
            'move',
            tr('Move tasks to {name}', {'name': personal.name}),
            ButtonKind.secondary,
          ),
          ('delete', tr('Delete company and its tasks'), ButtonKind.danger),
        ],
      );
    }
    if (choice == null || !mounted) return;
    Navigator.of(context).maybePop();
    app.store.deleteCompany(
      c,
      moveTasksTo: choice == 'move' ? personal.id : null,
    );
    app.toasts.show(tr('{name} deleted', {'name': c.name}));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final store = context.store;
    final company = store.company(widget.companyId);
    final preview = Company(
      id: '',
      name: _name.text,
      color: _color,
      icon: _icon,
      sortOrder: 0,
      createdAt: DateTime(0),
      updatedAt: DateTime(0),
    );
    return PanelPage(
      title: _isNew ? tr('New Company') : tr('Edit Company'),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 20),
        children: [
          Row(
            children: [
              CompanyAvatar(company: preview, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: DTextField(
                  controller: _name,
                  autofocus: _isNew,
                  filled: true,
                  hint: tr('Company name'),
                  style: Type.title,
                  onChanged: (v) {
                    setState(() {});
                    if (v.trim().isNotEmpty) _apply(name: v);
                  },
                  onSubmitted: (_) => _isNew ? _create() : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            tr('Colour'),
            style: Type.section.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in CompanyDefaults.palette)
                Hoverable(
                  onTap: () => _apply(color: c),
                  builder: (context, hovered, _) => AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 26,
                    height: 26,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == _color
                            ? Color(c)
                            : (hovered ? p.border : Colors.transparent),
                        width: 2,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            tr('Icon'),
            style: Type.section.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in companyIcons.entries)
                Hoverable(
                  onTap: () => _apply(icon: e.key),
                  builder: (context, hovered, _) {
                    final selected = e.key == _icon;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected
                            ? Color(_color)
                                  .withValues(alpha: p.isDark ? 0.28 : 0.16)
                            : hovered
                            ? p.hover
                            : p.field,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: selected ? Color(_color) : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        e.value,
                        size: 18,
                        color: selected ? Color(_color) : p.textSecondary,
                      ),
                    );
                  },
                ),
            ],
          ),
          if (company != null && !company.isPersonal) ...[
            const SizedBox(height: 28),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DButton(
                label: tr('Delete company…'),
                icon: Icons.delete_outline_rounded,
                kind: ButtonKind.danger,
                dense: true,
                onTap: () => _delete(company),
              ),
            ),
          ],
          if (company != null && company.isPersonal) ...[
            const SizedBox(height: 24),
            Text(
              tr('Personal is always kept so your own tasks have a home.'),
              style: Type.caption.copyWith(color: p.textTertiary),
            ),
          ],
        ],
      ),
      bottom: _isNew
          ? Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 12, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DButton(
                    label: tr('Cancel'),
                    kind: ButtonKind.ghost,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 6),
                  DButton(
                    label: tr('Add Company'),
                    kind: ButtonKind.primary,
                    onTap: _name.text.trim().isEmpty ? null : _create,
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

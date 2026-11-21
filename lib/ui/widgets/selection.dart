import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../controller.dart';
import '../theme.dart';
import 'common.dart';
import 'menus.dart';
import 'task_row.dart';
import '../../l10n/l10n.dart';

/// Multi-select state for a list: ⌘-click toggles, ⇧-click selects a range.
class Selection extends ChangeNotifier {
  final ids = <String>{};
  bool active = false;
  String? _anchor;

  void start() {
    active = true;
    notifyListeners();
  }

  void toggle(Task t) {
    active = true;
    if (!ids.remove(t.id)) ids.add(t.id);
    _anchor = t.id;
    notifyListeners();
  }

  void range(Task t, List<Task> visible) {
    active = true;
    final from = visible.indexWhere((x) => x.id == _anchor);
    final to = visible.indexWhere((x) => x.id == t.id);
    if (from < 0 || to < 0) {
      toggle(t);
      return;
    }
    final (a, b) = from < to ? (from, to) : (to, from);
    for (var i = a; i <= b; i++) {
      ids.add(visible[i].id);
    }
    notifyListeners();
  }

  void selectAll(List<Task> visible) {
    active = true;
    ids.addAll(visible.map((t) => t.id));
    notifyListeners();
  }

  void clear() {
    ids.clear();
    active = false;
    _anchor = null;
    notifyListeners();
  }

  bool contains(Task t) => ids.contains(t.id);

  List<Task> tasks(BuildContext context) {
    final store = context.store;
    return [for (final id in ids) ?store.task(id)];
  }
}

/// Bottom bar shown while tasks are selected.
class BatchBar extends StatelessWidget {
  const BatchBar({super.key, required this.selection, required this.visible});
  final Selection selection;
  final List<Task> visible;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final tasks = selection.tasks(context);
        final n = tasks.length;
        final enabled = n > 0;
        void done() => selection.clear();
        return Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              DIconButton(
                icon: Icons.close_rounded,
                tooltip: tr('Exit selection'),
                onTap: done,
              ),
              const SizedBox(width: 4),
              Text(
                n == 0 ? tr('Select tasks') : tr('{n} selected', {'n': n}),
                style: Type.bodyStrong.copyWith(color: p.text),
              ),
              const SizedBox(width: 6),
              LinkButton(
                n == visible.length && n > 0 ? tr('None') : tr('All'),
                onTap: () {
                  if (n == visible.length && n > 0) {
                    selection.ids.clear();
                    selection.start();
                  } else {
                    selection.selectAll(visible);
                  }
                },
              ),
              const Spacer(),
              DIconButton(
                icon: Icons.radio_button_unchecked_rounded,
                tooltip: tr('Move to To Do'),
                onTap: enabled
                    ? () => _status(app, tasks, TaskStatus.todo, done)
                    : null,
              ),
              DIconButton(
                icon: Icons.timelapse_rounded,
                tooltip: tr('Move to In Progress'),
                onTap: enabled
                    ? () => _status(app, tasks, TaskStatus.inProgress, done)
                    : null,
              ),
              DIconButton(
                icon: Icons.check_circle_outline_rounded,
                tooltip: tr('Complete'),
                onTap: enabled
                    ? () => _status(app, tasks, TaskStatus.done, done)
                    : null,
              ),
              Builder(
                builder: (context) => DIconButton(
                  icon: Icons.flag_outlined,
                  tooltip: tr('Priority'),
                  onTap: !enabled
                      ? null
                      : () async {
                          final pr = await showDocketMenu<Priority>(
                            context,
                            anchor: globalRect(context),
                            width: 160,
                            items: [
                              for (final x in Priority.values)
                                MenuItemX(label: x.label, value: x),
                            ],
                          );
                          if (pr != null) {
                            app.store.setPriorityMany(tasks, pr);
                            app.toasts.show(
                              tr('Priority set to {priority}', {
                                'priority': pr.label,
                              }),
                            );
                          }
                        },
                ),
              ),
              Builder(
                builder: (context) => DIconButton(
                  icon: Icons.drive_file_move_outline,
                  tooltip: tr('Move to company'),
                  onTap: !enabled
                      ? null
                      : () async {
                          final c = await pickCompany(
                            context,
                            anchor: globalRect(context),
                          );
                          if (c != null) {
                            app.store.moveMany(tasks, c.id);
                            app.toasts.show(
                              tr('Moved {n} to {company}', {
                                'n': n,
                                'company': c.name,
                              }),
                            );
                            done();
                          }
                        },
                ),
              ),
              DIconButton(
                icon: Icons.archive_outlined,
                tooltip: tr('Archive'),
                onTap: !enabled
                    ? null
                    : () {
                        app.store.archiveMany(tasks, true);
                        app.toasts.show(
                          tr('Archived {n}', {'n': n}),
                          actionLabel: tr('Undo'),
                          onAction: () => app.store.archiveMany(tasks, false),
                        );
                        done();
                      },
              ),
              DIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: tr('Delete'),
                color: p.urgent,
                onTap: !enabled
                    ? null
                    : () async {
                        if (await app.deleteMany(context, tasks)) done();
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  void _status(
    AppController app,
    List<Task> tasks,
    TaskStatus status,
    VoidCallback done,
  ) {
    final changes = app.store.setStatusMany(tasks, status);
    if (changes.isEmpty) return;
    app.toasts.show(
      tr('{n} moved to {status}', {
        'n': changes.length,
        'status': status.label,
      }),
      actionLabel: tr('Undo'),
      onAction: () {
        for (final c in changes.reversed) {
          app.store.undoStatus(c);
        }
      },
    );
    done();
  }
}

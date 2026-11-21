import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../l10n/l10n.dart';
import '../controller.dart';
import '../theme.dart';
import 'common.dart';
import 'menus.dart';
import 'task_row.dart';

/// The session list: what you plan to do in this sitting (an hour, two, or
/// the day). Its own items, apart from company tasks. Ticked items stay at the
/// bottom, crossed out, until you clear them or start a new session.
class SessionList extends StatefulWidget {
  const SessionList({super.key});

  @override
  State<SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<SessionList> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String text) {
    context.store.addSessionItem(text);
    _controller.clear();
    _focus.requestFocus();
  }

  void _delete(SessionItem item) {
    final app = context.app;
    app.store.deleteSessionItem(item);
    app.toasts.show(
      tr('Removed from the session'),
      actionLabel: tr('Undo'),
      onAction: () => app.store.restoreSessionItems([item]),
    );
  }

  Future<void> _menu(BuildContext anchorContext) async {
    final app = context.app;
    final store = app.store;
    final hasDone = store.sessionItems.any((i) => i.done);
    final value = await showDocketMenu<String>(
      anchorContext,
      anchor: globalRect(anchorContext),
      width: 220,
      items: [
        MenuItemX(
          label: tr('New session'),
          value: 'new',
          icon: Icons.restart_alt_rounded,
        ),
        if (hasDone)
          MenuItemX(
            label: tr('Clear completed'),
            value: 'clear',
            icon: Icons.cleaning_services_outlined,
          ),
        const MenuDivider(),
        MenuItemX(
          label: tr('Hide session'),
          value: 'hide',
          icon: Icons.visibility_off_outlined,
        ),
      ],
    );
    if (!mounted) return;
    switch (value) {
      case 'new':
        final (items, started) = store.startNewSession();
        _focus.requestFocus();
        if (items.isNotEmpty) {
          app.toasts.show(
            tr('New session started'),
            actionLabel: tr('Undo'),
            onAction: () =>
                store.restoreSessionItems(items, startedAt: started),
          );
        }
      case 'clear':
        final items = store.clearCompletedSession();
        app.toasts.show(
          tr('Completed items cleared'),
          actionLabel: tr('Undo'),
          onAction: () => store.restoreSessionItems(items),
        );
      case 'hide':
        store.updateSettings((s) => s.curtainShowSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return StoreBuilder(
      builder: (context) {
        final store = context.store;
        final items = store.sessionItems;
        final open = items.where((i) => !i.done).toList();
        final done = items.where((i) => i.done).toList();

        final rows = <Widget>[
          for (final i in open)
            _SessionRow(
              key: ValueKey(i.id),
              item: i,
              onDelete: () => _delete(i),
            ),
          if (done.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 8, 4),
              child: Row(
                children: [
                  Text(
                    tr('Completed'),
                    style: Type.captionStrong.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${done.length}',
                    style: Type.captionStrong.copyWith(color: p.textTertiary),
                  ),
                ],
              ),
            ),
            for (final i in done)
              _SessionRow(
                key: ValueKey(i.id),
                item: i,
                onDelete: () => _delete(i),
              ),
          ],
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 8),
              child: _Header(
                open: open.length,
                done: done.length,
                onMenu: _menu,
              ),
            ),
            Container(height: 1, color: p.divider),
            Expanded(
              child: items.isEmpty
                  ? _Empty(onStart: _focus.requestFocus)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                      children: rows,
                    ),
            ),
            Container(height: 1, color: p.divider),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 10),
              child: Container(
                height: 34,
                padding: const EdgeInsetsDirectional.only(start: 10, end: 8),
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
                      child: DTextField(
                        controller: _controller,
                        focusNode: _focus,
                        hint: tr('Add to this session…'),
                        onSubmitted: _add,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.open, required this.done, required this.onMenu});
  final int open;
  final int done;
  final Future<void> Function(BuildContext anchor) onMenu;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final store = context.store;
    final now = store.now;
    final started = store.settings.sessionStartedAt;
    final total = open + done;
    final use24h = store.settings.use24h;
    final subtitle = started == null || total == 0
        ? tr('What will you get done now?')
        : [
            tr('Started {time}', {
              'time': sameDay(started, now)
                  ? formatClock(started, use24h: use24h)
                  : formatStamp(started, now, use24h: use24h),
            }),
            tr('{duration} so far', {
              'duration': formatDuration(now.difference(started)),
            }),
          ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: p.accentSoft,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(Icons.bolt_rounded, size: 17, color: p.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tr('Session'),
                        style: Type.bodyStrong.copyWith(
                          color: p.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (total > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          tr('{done} of {total}', {
                            'done': done,
                            'total': total,
                          }),
                          style: Type.small.copyWith(color: p.textTertiary),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            Builder(
              builder: (context) => DIconButton(
                icon: Icons.more_horiz_rounded,
                size: 26,
                iconSize: 16,
                tooltip: tr('More'),
                onTap: () => onMenu(context),
              ),
            ),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: done / total),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 3,
                backgroundColor: p.field,
                valueColor: AlwaysStoppedAnimation(p.success),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 28, color: p.textTertiary),
            const SizedBox(height: 8),
            Text(
              tr('Plan this session'),
              style: Type.bodyStrong.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Write what you’ll work on for the next hour, two, or today.'),
              textAlign: TextAlign.center,
              style: Type.small.copyWith(color: p.textTertiary),
            ),
            const SizedBox(height: 10),
            LinkButton(tr('Write the first one'), onTap: onStart),
          ],
        ),
      ),
    );
  }
}

/// One line: tick, title (click to edit), delete on hover.
class _SessionRow extends StatefulWidget {
  const _SessionRow({super.key, required this.item, required this.onDelete});
  final SessionItem item;
  final VoidCallback onDelete;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _finish(save: true);
    });
  }

  void _edit() {
    _controller.text = widget.item.title;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _finish({required bool save}) {
    if (save) context.store.renameSessionItem(widget.item, _controller.text);
    if (mounted) setState(() => _editing = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final item = widget.item;
    final style = Type.body.copyWith(
      color: item.done ? p.textTertiary : p.text,
      decoration: item.done ? TextDecoration.lineThrough : null,
      decorationColor: p.textTertiary,
    );
    return Hoverable(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsetsDirectional.fromSTEB(8, 7, 4, 7),
        decoration: BoxDecoration(
          color: _editing
              ? p.field
              : hovered
              ? p.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DoneCircle(
              done: item.done,
              onTap: () => context.store.toggleSessionItem(item),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _editing
                  ? CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.escape): () {
                          _finish(save: false);
                        },
                      },
                      child: DTextField(
                        controller: _controller,
                        focusNode: _focus,
                        style: style,
                        onSubmitted: (_) => _finish(save: true),
                      ),
                    )
                  : GestureDetector(
                      onTap: _edit,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.text,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 0.5),
                          child: AutoText(item.title, style: style),
                        ),
                      ),
                    ),
            ),
            SizedBox(
              width: 22,
              height: 20,
              child: hovered && !_editing
                  ? DIconButton(
                      icon: Icons.close_rounded,
                      size: 20,
                      iconSize: 13,
                      tooltip: tr('Remove'),
                      onTap: widget.onDelete,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

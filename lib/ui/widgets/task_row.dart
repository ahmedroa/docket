import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../controller.dart';
import '../theme.dart';
import 'common.dart';
import 'menus.dart';
import '../../l10n/l10n.dart';

/// Circle that shows and toggles status: empty (to do), half (in progress), check (done).
class StatusCircle extends StatelessWidget {
  const StatusCircle({
    super.key,
    required this.task,
    this.onTap,
    this.size = 18,
  });
  final Task task;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: task.isDone ? tr('Reopen') : tr('Complete  ⌘↵'),
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered, pressed) => AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: pressed ? 0.88 : 1,
          child: SizedBox(
            width: size,
            height: size,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: CustomPaint(
                key: ValueKey('${task.status}-$hovered'),
                size: Size.square(size),
                painter: _StatusPainter(
                  status: task.status,
                  hovered: hovered,
                  ring: task.isUrgent && task.isOpen
                      ? p.urgent
                      : p.textTertiary,
                  progress: p.progress,
                  done: p.success,
                  check: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The same round tick for things that are only done or not (session items).
class DoneCircle extends StatelessWidget {
  const DoneCircle({
    super.key,
    required this.done,
    required this.onTap,
    this.size = 18,
  });
  final bool done;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: done ? tr('Reopen') : tr('Done'),
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered, pressed) => AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: pressed ? 0.88 : 1,
          child: CustomPaint(
            size: Size.square(size),
            painter: _StatusPainter(
              status: done ? TaskStatus.done : TaskStatus.todo,
              hovered: hovered,
              ring: p.textTertiary,
              progress: p.progress,
              done: p.success,
              check: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPainter extends CustomPainter {
  _StatusPainter({
    required this.status,
    required this.hovered,
    required this.ring,
    required this.progress,
    required this.done,
    required this.check,
  });

  final TaskStatus status;
  final bool hovered;
  final Color ring;
  final Color progress;
  final Color done;
  final Color check;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    void drawCheck(Color color, double alpha) {
      final path = Path()
        ..moveTo(c.dx - r * 0.42, c.dy + r * 0.02)
        ..lineTo(c.dx - r * 0.1, c.dy + r * 0.34)
        ..lineTo(c.dx + r * 0.45, c.dy - r * 0.3);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    switch (status) {
      case TaskStatus.todo:
        canvas.drawCircle(c, r, stroke..color = ring);
        if (hovered) drawCheck(ring, 0.8);
      case TaskStatus.inProgress:
        canvas.drawCircle(c, r, stroke..color = progress);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r - 2.6),
          -math.pi / 2,
          math.pi,
          true,
          Paint()..color = progress,
        );
        if (hovered) {
          canvas.drawCircle(
            c,
            r - 2.6,
            Paint()..color = progress.withValues(alpha: 0.25),
          );
        }
      case TaskStatus.done:
        canvas.drawCircle(
          c,
          r + 0.5,
          Paint()..color = hovered ? done.withValues(alpha: 0.7) : done,
        );
        drawCheck(check, 1);
    }
  }

  @override
  bool shouldRepaint(_StatusPainter old) =>
      old.status != status || old.hovered != hovered || old.ring != ring;
}

/// "Urgent" / "Low" pill; Normal shows only a faint flag on hover. Click to change.
class PriorityTag extends StatelessWidget {
  const PriorityTag({
    super.key,
    required this.task,
    this.showNormal = false,
    this.muted = false,
  });
  final Task task;
  final bool showNormal;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final priority = task.priority;
    if (priority == Priority.normal && !showNormal) {
      return const SizedBox.shrink();
    }
    return Builder(
      builder: (context) => Tooltip(
        message: tr('Priority'),
        child: Hoverable(
          onTap: () =>
              showPriorityMenu(context, task, anchor: globalRect(context)),
          builder: (context, hovered, _) {
            final (
              Color bg,
              Color fg,
              IconData icon,
              String? label,
            ) = switch (priority) {
              Priority.urgent => (
                p.urgentSoft,
                p.urgent,
                Icons.flag_rounded,
                tr('Urgent'),
              ),
              Priority.low => (
                p.field,
                p.textTertiary,
                Icons.south_rounded,
                tr('Low'),
              ),
              Priority.normal => (
                Colors.transparent,
                p.textTertiary,
                Icons.outlined_flag_rounded,
                null,
              ),
            };
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: muted ? 0.55 : 1,
              child: Container(
                height: 20,
                padding: EdgeInsets.symmetric(
                  horizontal: label == null ? 3 : 6,
                ),
                decoration: BoxDecoration(
                  color: hovered ? Color.alphaBlend(p.hover, bg) : bg,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: fg),
                    if (label != null) ...[
                      const SizedBox(width: 3),
                      Text(
                        label,
                        style: Type.captionStrong.copyWith(color: fg),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<void> showPriorityMenu(
  BuildContext context,
  Task task, {
  Rect? anchor,
  Offset? at,
}) async {
  final app = context.app;
  final p = context.palette;
  final value = await showDocketMenu<Priority>(
    context,
    anchor: anchor,
    at: at,
    width: 170,
    items: [
      for (final pr in Priority.values)
        MenuItemX(
          label: pr.label,
          value: pr,
          checked: task.priority == pr,
          icon: switch (pr) {
            Priority.urgent => Icons.flag_rounded,
            Priority.normal => Icons.outlined_flag_rounded,
            Priority.low => Icons.south_rounded,
          },
          iconColor: pr == Priority.urgent ? p.urgent : p.textSecondary,
        ),
    ],
  );
  if (value != null) app.setPriority(task, value);
}

/// Due date in words, coloured by urgency (overdue / today / later).
class DueLabel extends StatelessWidget {
  const DueLabel({super.key, required this.task, this.compact = false});
  final Task task;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = task.dueDate;
    if (d == null) return const SizedBox.shrink();
    final p = context.palette;
    final app = context.app;
    final now = app.store.now;
    final use24h = app.store.settings.use24h;
    final overdue = task.isOverdue(now);
    final today = sameDay(d, now);
    final time = task.dueMinutes == null
        ? ''
        : ' ${formatTimeOfDay(task.dueMinutes!, use24h: use24h)}';
    final text = overdue
        ? (today
              ? '${tr('Overdue')}$time'
              : '${tr('Overdue')} · ${formatRelativeDay(d, now)}')
        : '${formatRelativeDay(d, now)}$time';
    final color = !task.isOpen
        ? p.textTertiary
        : overdue
        ? p.warning
        : today
        ? p.accent
        : p.textSecondary;
    return MetaItem(
      icon: overdue ? Icons.schedule_rounded : Icons.calendar_today_rounded,
      text: text,
      color: color,
      strong: task.isOpen && (overdue || today),
    );
  }
}

/// Icon + caption used in task metadata rows.
class MetaItem extends StatelessWidget {
  const MetaItem({
    super.key,
    this.icon,
    required this.text,
    this.color,
    this.strong = false,
  });
  final IconData? icon;
  final String text;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 3),
        ],
        Text(
          text,
          textDirection: dirOf(context, text),
          style: (strong ? Type.captionStrong : Type.caption).copyWith(
            color: c,
          ),
        ),
      ],
    );
  }
}

/// One task in any list.
class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    this.showCompany = false,
    this.showAdded = false,
    this.reorderIndex,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
    this.onRangeSelect,
    this.showDescription = true,
  });

  final Task task;
  final bool showCompany;
  final bool showAdded;

  /// When set, a drag handle appears on hover for manual ordering.
  final int? reorderIndex;
  final bool selectionMode;
  final bool selected;
  final void Function(Task task)? onSelect;
  final void Function(Task task)? onRangeSelect;
  final bool showDescription;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _hovered = false;

  void _tap() {
    final app = context.app;
    if (widget.onSelect != null && (widget.selectionMode || isCommandPressed)) {
      widget.onSelect!(widget.task);
    } else if (widget.onRangeSelect != null && isShiftPressed) {
      widget.onRangeSelect!(widget.task);
    } else {
      app.openTask(widget.task);
    }
  }

  void _hover(bool hovered) {
    setState(() => _hovered = hovered);
    final app = context.app;
    if (hovered) {
      app.activeTaskId = widget.task.id;
    } else if (app.activeTaskId == widget.task.id) {
      app.activeTaskId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    final store = app.store;
    final t = widget.task;
    final now = store.now;
    final company = store.company(t.companyId);
    final subtasks = t.liveSubtasks;
    final doneSubtasks = subtasks.where((s) => s.done).length;

    final meta = <Widget>[
      if (widget.showCompany && company != null) CompanyChip(company: company),
      if (t.dueDate != null) DueLabel(task: t),
      if (t.status == TaskStatus.inProgress && t.expectedDate != null)
        MetaItem(
          icon: Icons.event_available_outlined,
          text: tr('Expected {day}', {
            'day': formatRelativeDay(t.expectedDate!, now),
          }),
        ),
      if (t.timeSpentSeconds > 0 || t.isTimerRunning)
        MetaItem(
          icon: t.isTimerRunning ? Icons.timer_rounded : Icons.timer_outlined,
          text: formatDuration(t.timeSpent(now)),
          color: t.isTimerRunning ? p.progress : null,
          strong: t.isTimerRunning,
        ),
      if (subtasks.isNotEmpty)
        MetaItem(
          icon: Icons.checklist_rounded,
          text: '$doneSubtasks/${subtasks.length}',
          color: doneSubtasks == subtasks.length ? p.success : null,
        ),
      if (t.recurrence != Recurrence.none)
        MetaItem(icon: Icons.repeat_rounded, text: t.recurrence.label),
      if (t.notes.trim().isNotEmpty || t.liveUpdates.isNotEmpty)
        const MetaItem(icon: Icons.notes_rounded, text: ''),
      for (final tag in t.tags.take(3)) MetaItem(text: '#$tag'),
      if (t.isDone && t.completedAt != null)
        MetaItem(
          icon: Icons.check_rounded,
          text: tr('Done {day}', {
            'day': formatRelativeDay(t.completedAt!, now),
          }),
        ),
      if (widget.showAdded && t.isOpen)
        MetaItem(
          text: tr('Added {when}', {'when': formatAgo(t.createdAt, now)}),
        ),
      if (widget.showAdded && t.isDone)
        MetaItem(
          text: tr('Added {when}', {'when': formatShortDate(t.createdAt, now)}),
        ),
    ];

    final hoverActions = <Widget>[
      if (_hovered && !widget.selectionMode) ...[
        if (t.status == TaskStatus.todo)
          DIconButton(
            icon: Icons.play_arrow_rounded,
            size: 22,
            iconSize: 15,
            tooltip: tr('Start'),
            onTap: () => app.setStatus(t, TaskStatus.inProgress),
          ),
        if (t.status == TaskStatus.inProgress)
          DIconButton(
            icon: t.isTimerRunning ? Icons.pause_rounded : Icons.timer_outlined,
            size: 22,
            iconSize: 15,
            tooltip: t.isTimerRunning ? tr('Stop timer') : tr('Start timer'),
            color: t.isTimerRunning ? p.progress : null,
            onTap: () =>
                t.isTimerRunning ? store.stopTimer(t) : store.startTimer(t),
          ),
        if (t.status == TaskStatus.done)
          DIconButton(
            icon: Icons.undo_rounded,
            size: 22,
            iconSize: 15,
            tooltip: tr('Reopen'),
            onTap: () => app.setStatus(t, TaskStatus.todo),
          ),
        Builder(
          builder: (context) => DIconButton(
            icon: Icons.more_horiz_rounded,
            size: 22,
            iconSize: 16,
            tooltip: tr('More'),
            onTap: () => showTaskMenu(context, t, anchor: globalRect(context)),
          ),
        ),
      ],
    ];

    final leading = widget.selectionMode
        ? _SelectBox(
            selected: widget.selected,
            onTap: () => widget.onSelect?.call(t),
          )
        : StatusCircle(task: t, onTap: () => app.toggleDone(t));

    return Hoverable(
      onTap: _tap,
      onHover: _hover,
      onSecondaryTapDown: (d) => showTaskMenu(context, t, at: d.globalPosition),
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered, pressed) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: widget.selected
                ? p.selected
                : pressed
                ? p.pressed
                : hovered
                ? p.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              if (t.isUrgent && t.isOpen)
                PositionedDirectional(
                  start: 0,
                  top: 9,
                  bottom: 9,
                  child: Container(
                    width: 2.5,
                    decoration: BoxDecoration(
                      color: p.urgent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 6, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 18,
                      child:
                          widget.reorderIndex != null &&
                              hovered &&
                              !widget.selectionMode
                          ? ReorderableDragStartListener(
                              index: widget.reorderIndex!,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 14,
                                  color: p.textTertiary,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 2),
                    Padding(
                      padding: const EdgeInsets.only(top: 0.5),
                      child: leading,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: AutoText(
                                    t.title.isEmpty ? tr('Untitled') : t.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Type.bodyStrong.copyWith(
                                      color: t.isDone
                                          ? p.textSecondary
                                          : p.text,
                                      decoration: t.isDone
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor: p.textTertiary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              PriorityTag(
                                task: t,
                                showNormal: hovered && t.isOpen,
                                muted: t.isDone,
                              ),
                              ...hoverActions,
                            ],
                          ),
                          if (widget.showDescription &&
                              t.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            AutoText(
                              t.description.trim().replaceAll('\n', ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Type.small.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(spacing: 10, runSpacing: 3, children: meta),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// How many completed tasks a list keeps at its bottom before "Show all".
const completedTailLimit = 10;

/// Completed tasks kept at the bottom of a list, ticked and crossed out:
/// a "Completed" header, the newest [limit] rows, then a link to the rest.
/// [done] is newest first.
List<Widget> completedTail(
  List<Task> done, {
  required Widget Function(Task t) row,
  VoidCallback? onShowAll,
  int limit = completedTailLimit,
}) {
  if (done.isEmpty) return const [];
  return [
    SectionHeader(tr('Completed'), count: done.length),
    for (final t in done.take(limit)) row(t),
    if (done.length > limit && onShowAll != null)
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(40, 4, 16, 0),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: LinkButton(
            tr('Show all {n} completed', {'n': done.length}),
            onTap: onShowAll,
          ),
        ),
      ),
  ];
}

class _SelectBox extends StatelessWidget {
  const _SelectBox({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: selected ? p.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? p.accent : p.textTertiary,
            width: 1.5,
          ),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 13, color: p.onAccent)
            : null,
      ),
    );
  }
}

enum _TaskMenuAction {
  open,
  todo,
  inProgress,
  done,
  urgent,
  normal,
  low,
  move,
  duplicate,
  archive,
  unarchive,
  delete,
}

/// Right-click / "⋯" menu for a task.
Future<void> showTaskMenu(
  BuildContext context,
  Task t, {
  Offset? at,
  Rect? anchor,
}) async {
  final app = context.app;
  final p = context.palette;
  final action = await showDocketMenu<_TaskMenuAction>(
    context,
    at: at,
    anchor: anchor,
    width: 210,
    items: [
      MenuItemX(
        label: tr('Open'),
        value: _TaskMenuAction.open,
        icon: Icons.open_in_full_rounded,
        shortcut: '↵',
      ),
      const MenuDivider(),
      MenuHeader(tr('Status')),
      MenuItemX(
        label: tr('To Do'),
        value: _TaskMenuAction.todo,
        checked: t.status == TaskStatus.todo,
      ),
      MenuItemX(
        label: tr('In Progress'),
        value: _TaskMenuAction.inProgress,
        checked: t.status == TaskStatus.inProgress,
      ),
      MenuItemX(
        label: tr('Completed'),
        value: _TaskMenuAction.done,
        checked: t.status == TaskStatus.done,
        shortcut: t.isDone ? null : '⌘↵',
      ),
      MenuHeader(tr('Priority')),
      MenuItemX(
        label: tr('Urgent'),
        value: _TaskMenuAction.urgent,
        checked: t.priority == Priority.urgent,
        icon: Icons.flag_rounded,
        iconColor: p.urgent,
      ),
      MenuItemX(
        label: tr('Normal'),
        value: _TaskMenuAction.normal,
        checked: t.priority == Priority.normal,
        icon: Icons.outlined_flag_rounded,
      ),
      MenuItemX(
        label: tr('Low'),
        value: _TaskMenuAction.low,
        checked: t.priority == Priority.low,
        icon: Icons.south_rounded,
      ),
      const MenuDivider(),
      MenuItemX(
        label: tr('Move to…'),
        value: _TaskMenuAction.move,
        icon: Icons.drive_file_move_outline,
      ),
      MenuItemX(
        label: tr('Duplicate'),
        value: _TaskMenuAction.duplicate,
        icon: Icons.copy_rounded,
      ),
      if (t.isArchived)
        MenuItemX(
          label: tr('Unarchive'),
          value: _TaskMenuAction.unarchive,
          icon: Icons.unarchive_outlined,
        )
      else
        MenuItemX(
          label: tr('Archive'),
          value: _TaskMenuAction.archive,
          icon: Icons.archive_outlined,
        ),
      const MenuDivider(),
      MenuItemX(
        label: tr('Delete…'),
        value: _TaskMenuAction.delete,
        icon: Icons.delete_outline_rounded,
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _TaskMenuAction.open:
      app.openTask(t);
    case _TaskMenuAction.todo:
      app.setStatus(t, TaskStatus.todo);
    case _TaskMenuAction.inProgress:
      app.setStatus(t, TaskStatus.inProgress);
    case _TaskMenuAction.done:
      app.setStatus(t, TaskStatus.done);
    case _TaskMenuAction.urgent:
      app.setPriority(t, Priority.urgent);
    case _TaskMenuAction.normal:
      app.setPriority(t, Priority.normal);
    case _TaskMenuAction.low:
      app.setPriority(t, Priority.low);
    case _TaskMenuAction.move:
      final c = await pickCompany(
        context,
        at: at,
        anchor: anchor,
        current: t.companyId,
      );
      if (c != null) app.moveTo(t, c);
    case _TaskMenuAction.duplicate:
      app.duplicate(t);
    case _TaskMenuAction.archive:
      app.archive(t);
    case _TaskMenuAction.unarchive:
      app.unarchive(t);
    case _TaskMenuAction.delete:
      await app.deleteTask(context, t);
  }
}

Future<Company?> pickCompany(
  BuildContext context, {
  Offset? at,
  Rect? anchor,
  String? current,
}) {
  final store = context.store;
  return showDocketMenu<Company>(
    context,
    at: at,
    anchor: anchor,
    width: 220,
    items: [
      for (final c in store.companies)
        MenuItemX(
          label: c.name,
          value: c,
          checked: c.id == current,
          leading: CompanyAvatar(company: c, size: 18),
        ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../controller.dart';
import '../theme.dart';
import 'common.dart';
import 'menus.dart';
import '../../l10n/l10n.dart';

/// Sentinel returned by pickers when the user clears the value.
class Cleared {
  const Cleared();
}

/// Compact button showing a date; opens a calendar popover.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.warn = false,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? placeholder;

  /// Shown in the overdue colour.
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final now = context.store.now;
    final v = value;
    final past = v != null && warn;
    return Builder(
      builder: (context) => FieldButton(
        icon: Icons.calendar_today_rounded,
        label: v == null ? (placeholder ?? tr('No date')) : _label(v, now),
        placeholder: v == null,
        color: past ? p.warning : null,
        onTap: () async {
          final result = await showCalendar(
            context,
            anchor: globalRect(context),
            initial: v,
          );
          if (result is DateTime) onChanged(result);
          if (result is Cleared) onChanged(null);
        },
        onClear: v == null ? null : () => onChanged(null),
      ),
    );
  }

  static String _label(DateTime d, DateTime now) {
    final rel = formatRelativeDay(d, now);
    final short = formatShortDate(d, now);
    return rel == short ? short : '$rel${L10n.isArabic ? '،' : ','} $short';
  }
}

/// Time button; offers common times and accepts typed input ("2pm", "14:30").
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.minutes,
    required this.onChanged,
    this.enabled = true,
  });
  final int? minutes;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final use24h = context.store.settings.use24h;
    return Builder(
      builder: (context) => FieldButton(
        icon: Icons.schedule_rounded,
        label: minutes == null
            ? tr('Any time')
            : formatTimeOfDay(minutes!, use24h: use24h),
        placeholder: minutes == null,
        onTap: !enabled
            ? null
            : () async {
                final result = await showAnchored<Object>(
                  context,
                  anchor: globalRect(context),
                  width: 200,
                  builder: (context) =>
                      _TimeMenu(current: minutes, use24h: use24h),
                );
                if (result is int) onChanged(result);
                if (result is Cleared) onChanged(null);
              },
        onClear: minutes == null || !enabled ? null : () => onChanged(null),
      ),
    );
  }
}

/// A subtle bordered button with optional clear "×".
class FieldButton extends StatelessWidget {
  const FieldButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.placeholder = false,
    this.onClear,
    this.color,
    this.trailingChevron = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? leading;
  final bool placeholder;
  final VoidCallback? onClear;
  final Color? color;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = color ?? (placeholder ? p.textTertiary : p.text);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 26,
        padding: EdgeInsetsDirectional.only(
          start: 8,
          end: onClear != null ? 3 : 8,
        ),
        decoration: BoxDecoration(
          color: hovered && onTap != null ? p.pressed : p.field,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            if (icon != null) ...[
              Icon(icon, size: 13, color: color ?? p.textSecondary),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                textDirection: dirOf(context, label),
                overflow: TextOverflow.ellipsis,
                style: Type.small.copyWith(color: fg),
              ),
            ),
            if (trailingChevron) ...[
              const SizedBox(width: 3),
              Icon(Icons.expand_more_rounded, size: 14, color: p.textTertiary),
            ],
            if (onClear != null) ...[
              const SizedBox(width: 2),
              Hoverable(
                onTap: onClear,
                builder: (context, h, _) => Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: h ? p.pressed : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: p.textTertiary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeMenu extends StatefulWidget {
  const _TimeMenu({required this.current, required this.use24h});
  final int? current;
  final bool use24h;

  @override
  State<_TimeMenu> createState() => _TimeMenuState();
}

class _TimeMenuState extends State<_TimeMenu> {
  final _controller = TextEditingController();
  bool _invalid = false;

  static const presets = [
    9 * 60,
    10 * 60,
    12 * 60,
    14 * 60,
    16 * 60,
    17 * 60,
    20 * 60,
  ];

  void _submit(String text) {
    final m = parseTimeInput(text);
    if (m == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(m);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DTextField(
            controller: _controller,
            autofocus: true,
            filled: true,
            hint: widget.use24h
                ? tr('Type a time, e.g. 14:30')
                : tr('Type a time, e.g. 2:30 pm'),
            style: Type.small,
            onSubmitted: _submit,
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
          ),
          if (_invalid)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4, start: 2),
              child: Text(
                tr("Couldn't read that time"),
                style: Type.caption.copyWith(color: p.urgent),
              ),
            ),
          const SizedBox(height: 6),
          for (final m in presets)
            _PresetRow(
              label: formatTimeOfDay(m, use24h: widget.use24h),
              selected: m == widget.current,
              onTap: () => Navigator.of(context).pop(m),
            ),
          if (widget.current != null) ...[
            Container(
              height: 1,
              color: p.divider,
              margin: const EdgeInsets.symmetric(vertical: 4),
            ),
            _PresetRow(
              label: tr('Remove time'),
              onTap: () => Navigator.of(context).pop(const Cleared()),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      onTap: onTap,
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered, _) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          color: hovered
              ? p.accent
              : (selected ? p.accentSoft : Colors.transparent),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: Type.small.copyWith(color: hovered ? Colors.white : p.text),
        ),
      ),
    );
  }
}

/// Calendar popover with quick picks. Returns a [DateTime], [Cleared] or null.
Future<Object?> showCalendar(
  BuildContext context, {
  required Rect anchor,
  DateTime? initial,
}) {
  return showAnchored<Object>(
    context,
    anchor: anchor,
    width: 252,
    builder: (context) => CalendarPicker(initial: initial),
  );
}

class CalendarPicker extends StatefulWidget {
  const CalendarPicker({super.key, this.initial});
  final DateTime? initial;

  @override
  State<CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends State<CalendarPicker> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final base = widget.initial ?? DateTime.now();
    _month = DateTime(base.year, base.month);
  }

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final now = context.store.now;
    final today = dateOnly(now);
    // Weeks start on Sunday.
    final first = DateTime(_month.year, _month.month, 1);
    final gridStart = addDays(first, -(first.weekday % 7));
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((first.weekday % 7) + daysInMonth) > 35 ? 42 : 35;
    final nextWeek = addDays(today, 7 - (today.weekday % 7));

    void pick(DateTime d) => Navigator.of(context).pop(d);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): () =>
            _shift(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): () =>
            _shift(1),
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _Quick(label: tr('Today'), onTap: () => pick(today)),
                  const SizedBox(width: 4),
                  _Quick(
                    label: tr('Tomorrow'),
                    onTap: () => pick(addDays(today, 1)),
                  ),
                  const SizedBox(width: 4),
                  _Quick(label: tr('Next week'), onTap: () => pick(nextWeek)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Text(
                    '${monthsLong[_month.month - 1]} ${_month.year}',
                    style: Type.bodyStrong.copyWith(color: p.text),
                  ),
                  const Spacer(),
                  DIconButton(
                    icon: Icons.chevron_left_rounded,
                    size: 24,
                    iconSize: 18,
                    onTap: () => _shift(-1),
                  ),
                  DIconButton(
                    icon: Icons.chevron_right_rounded,
                    size: 24,
                    iconSize: 18,
                    onTap: () => _shift(1),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final w in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                    Expanded(
                      child: Center(
                        child: Text(
                          w,
                          style: Type.caption.copyWith(color: p.textTertiary),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              for (var row = 0; row < cells ~/ 7; row++)
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _DayCell(
                          day: addDays(gridStart, row * 7 + col),
                          inMonth:
                              addDays(gridStart, row * 7 + col).month ==
                              _month.month,
                          isToday: sameDay(
                            addDays(gridStart, row * 7 + col),
                            today,
                          ),
                          selected:
                              widget.initial != null &&
                              sameDay(
                                addDays(gridStart, row * 7 + col),
                                widget.initial!,
                              ),
                          onTap: pick,
                        ),
                      ),
                  ],
                ),
              if (widget.initial != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: LinkButton(
                    tr('Remove date'),
                    color: p.textSecondary,
                    onTap: () => Navigator.of(context).pop(const Cleared()),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DButton(label: label, dense: true, onTap: onTap),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool selected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      onTap: () => onTap(day),
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered, _) => Container(
        height: 30,
        alignment: Alignment.center,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? p.accent
                : hovered
                ? p.hover
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${day.day}',
            style: Type.small.copyWith(
              fontWeight: isToday || selected
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: selected
                  ? p.onAccent
                  : isToday
                  ? p.accent
                  : inMonth
                  ? p.text
                  : p.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

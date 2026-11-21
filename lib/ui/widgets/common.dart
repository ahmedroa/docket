import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../controller.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';

/// Hover-aware builder (macOS has no ripples; hover and press states carry feedback).
class Hoverable extends StatefulWidget {
  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTapDown,
    this.onHover,
    this.cursor,
  });

  final Widget Function(BuildContext context, bool hovered, bool pressed)
  builder;
  final VoidCallback? onTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final void Function(bool hovered)? onHover;
  final MouseCursor? cursor;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          widget.cursor ??
          (widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer),
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover?.call(true);
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
        widget.onHover?.call(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = false),
        onTapCancel: widget.onTap == null
            ? null
            : () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: widget.builder(context, _hovered, _pressed),
      ),
    );
  }
}

class DIconButton extends StatelessWidget {
  const DIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 28,
    this.iconSize = 17,
    this.color,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget button = Hoverable(
      onTap: onTap,
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active
              ? p.accentSoft
              : pressed
              ? p.pressed
              : hovered
              ? p.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: onTap == null
              ? p.textTertiary
              : active
              ? p.accent
              : (color ?? p.textSecondary),
        ),
      ),
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

enum ButtonKind { primary, secondary, ghost, danger }

class DButton extends StatelessWidget {
  const DButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = ButtonKind.secondary,
    this.icon,
    this.hint,
    this.expand = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onTap;
  final ButtonKind kind;
  final IconData? icon;

  /// Keyboard hint shown faintly after the label ("⌘↵").
  final String? hint;
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    final (Color bg, Color hoverBg, Color fg) = switch (kind) {
      ButtonKind.primary => (
        p.accent,
        Color.alphaBlend(Colors.white.withValues(alpha: 0.1), p.accent),
        p.onAccent,
      ),
      ButtonKind.secondary => (p.field, p.pressed, p.text),
      ButtonKind.ghost => (Colors.transparent, p.hover, p.textSecondary),
      ButtonKind.danger => (
        p.urgentSoft,
        p.urgent.withValues(alpha: 0.18),
        p.urgent,
      ),
    };
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, pressed) => AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? (pressed ? 0.85 : 1) : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: dense ? 26 : 30,
          padding: EdgeInsets.symmetric(horizontal: dense ? 9 : 12),
          decoration: BoxDecoration(
            color: hovered && enabled ? hoverBg : bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                textDirection: dirOf(context, label),
                style: Type.bodyStrong.copyWith(
                  color: fg,
                  fontSize: dense ? 12 : 13,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Text(
                  hint!,
                  textDirection: TextDirection.ltr,
                  style: Type.caption.copyWith(
                    color: fg.withValues(alpha: 0.6),
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

/// Rounded tile with the company's colour and icon.
class CompanyAvatar extends StatelessWidget {
  const CompanyAvatar({super.key, required this.company, this.size = 26});
  final Company company;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(company.color);
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? 0.24 : 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(companyIcon(company.icon), size: size * 0.6, color: color),
    );
  }
}

/// Small coloured dot + company name.
class CompanyChip extends StatelessWidget {
  const CompanyChip({super.key, required this.company, this.style});
  final Company company;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: Color(company.color),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            company.name,
            textDirection: dirOf(context, company.name),
            overflow: TextOverflow.ellipsis,
            style: style ?? Type.caption.copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.count,
    this.trailing,
    this.padding,
  });
  final String title;
  final int? count;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: padding ?? const EdgeInsetsDirectional.fromSTEB(16, 14, 10, 4),
      child: SizedBox(
        height: 22,
        child: Row(
          children: [
            Text(title, style: Type.section.copyWith(color: p.textSecondary)),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: Type.section.copyWith(color: p.textTertiary),
              ),
            ],
            const Spacer(),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Text button used for "Show all", "Edit" and similar links.
class LinkButton extends StatelessWidget {
  const LinkButton(
    this.label, {
    super.key,
    required this.onTap,
    this.icon,
    this.color,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: hovered ? p.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textDirection: dirOf(context, label),
              style: Type.caption.copyWith(
                color: color ?? p.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 2),
              Icon(icon, size: 13, color: color ?? p.accent),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pill used for filters and quick choices.
class ChoiceChipX extends StatelessWidget {
  const ChoiceChipX({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.accent;
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: selected
              ? c.withValues(alpha: p.isDark ? 0.24 : 0.12)
              : hovered
              ? p.pressed
              : p.field,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? c.withValues(alpha: 0.45) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 5)],
            if (icon != null) ...[
              Icon(icon, size: 13, color: selected ? c : p.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              textDirection: dirOf(context, label),
              style: Type.small.copyWith(
                color: selected ? c : p.text,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// macOS-style segmented control.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labels,
    this.colors,
    this.height = 28,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Widget Function(T option, bool selected)? labels;
  final Map<T, Color>? colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Hoverable(
                onTap: () => onChanged(o),
                builder: (context, hovered, _) {
                  final selected = o == value;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? (p.isDark ? const Color(0xFF48484A) : Colors.white)
                          : hovered
                          ? p.hover
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: selected && !p.isDark
                          ? [
                              const BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child:
                          labels?.call(o, selected) ??
                          Text(
                            '$o',
                            style: Type.small.copyWith(
                              color: selected
                                  ? (colors?[o] ?? p.text)
                                  : p.textSecondary,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact switch sized for 13pt rows.
class MiniSwitch extends StatelessWidget {
  const MiniSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 32,
          height: 19,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value
                ? p.accent
                : (p.isDark
                      ? const Color(0xFF48484A)
                      : const Color(0xFFDADADD)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: value
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: Container(
              width: 15,
              height: 15,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Borderless text input with automatic Arabic/English direction.
class DTextField extends StatefulWidget {
  const DTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.style,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.filled = false,
    this.prefix,
    this.suffix,
    this.padding,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final TextStyle? style;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final bool filled;
  final Widget? prefix;
  final Widget? suffix;
  final EdgeInsetsGeometry? padding;
  final TextInputAction? textInputAction;

  @override
  State<DTextField> createState() => _DTextFieldState();
}

class _DTextFieldState extends State<DTextField> {
  late TextEditingController _controller =
      widget.controller ?? TextEditingController();

  /// Direction of what's typed; empty fields follow the interface.
  TextDirection? _direction;

  @override
  void initState() {
    super.initState();
    _direction = strongDirection(_controller.text);
    _controller.addListener(_updateDirection);
  }

  @override
  void didUpdateWidget(DTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && widget.controller != _controller) {
      _controller.removeListener(_updateDirection);
      _controller = widget.controller!;
      _controller.addListener(_updateDirection);
    }
  }

  void _updateDirection() {
    final d = strongDirection(_controller.text);
    if (d != _direction) setState(() => _direction = d);
  }

  @override
  void dispose() {
    _controller.removeListener(_updateDirection);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = (widget.style ?? Type.body).copyWith(
      color: (widget.style?.color) ?? p.text,
    );
    final field = TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      style: style,
      textDirection: _direction ?? Directionality.of(context),
      // Mixed-script text keeps its reading order but sits on the interface's start edge.
      textAlign: Directionality.of(context) == TextDirection.rtl
          ? TextAlign.right
          : TextAlign.left,
      cursorWidth: 1.5,
      cursorHeight: (style.fontSize ?? 13) + 3,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        isDense: true,
        isCollapsed: true,
        border: InputBorder.none,
        hintText: widget.hint,
        hintTextDirection: Directionality.of(context),
        hintStyle: style.copyWith(color: p.textTertiary),
        contentPadding: EdgeInsets.zero,
      ),
    );
    if (!widget.filled && widget.prefix == null && widget.suffix == null) {
      return field;
    }
    return Container(
      padding:
          widget.padding ??
          const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: widget.filled
          ? BoxDecoration(
              color: p.field,
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        crossAxisAlignment: widget.maxLines == 1
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (widget.prefix != null) ...[
            widget.prefix!,
            const SizedBox(width: 7),
          ],
          Expanded(child: field),
          if (widget.suffix != null) ...[
            const SizedBox(width: 6),
            widget.suffix!,
          ],
        ],
      ),
    );
  }
}

/// Text that picks its own direction (Arabic titles read right-to-left).
class AutoText extends StatelessWidget {
  const AutoText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final ambient = Directionality.of(context);
    final dir = strongDirection(text) ?? ambient;
    // Text in the other script keeps its own reading order but stays aligned
    // with the interface's start edge, next to the status circle.
    final t = Text(
      text,
      textDirection: dir,
      textAlign: ambient == TextDirection.rtl
          ? TextAlign.right
          : TextAlign.left,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
    return dir == ambient ? t : SizedBox(width: double.infinity, child: t);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.field,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: p.textTertiary),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: Type.bodyStrong.copyWith(color: p.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: Type.small.copyWith(color: p.textTertiary),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

/// Header + body + optional pinned bottom bar; the frame for every sub-page.
class PanelPage extends StatelessWidget {
  const PanelPage({
    super.key,
    this.title,
    this.titleWidget,
    this.actions = const [],
    required this.body,
    this.bottom,
    this.showBack = true,
    this.headerBottom,
  });

  final String? title;
  final Widget? titleWidget;
  final List<Widget> actions;
  final Widget body;
  final Widget? bottom;
  final bool showBack;

  /// Content pinned under the header (tabs, filters).
  final Widget? headerBottom;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canPop = Navigator.of(context).canPop();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (showBack && canPop)
                    DIconButton(
                      icon: Icons.chevron_left_rounded,
                      iconSize: 22,
                      tooltip: tr('Back  ⌘['),
                      onTap: () => Navigator.of(context).maybePop(),
                    )
                  else
                    const SizedBox(width: 6),
                  const SizedBox(width: 4),
                  Expanded(
                    child:
                        titleWidget ??
                        Text(
                          title ?? '',
                          style: Type.title.copyWith(color: p.text),
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                  for (final a in actions) ...[const SizedBox(width: 2), a],
                ],
              ),
            ),
          ),
          ?headerBottom,
          Container(height: 1, color: p.divider),
          Expanded(child: body),
          if (bottom != null) ...[
            Container(height: 1, color: p.divider),
            bottom!,
          ],
        ],
      ),
    );
  }
}

/// Keyboard hint like "⌘N" rendered as a faint key cap.
class KeyHint extends StatelessWidget {
  const KeyHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        textDirection: TextDirection.ltr,
        style: Type.caption.copyWith(color: p.textTertiary, fontSize: 10),
      ),
    );
  }
}

/// Page-level shortcuts that keep working after a text field loses focus:
/// clicking outside a field moves focus to the nearest scope, which is inside here.
class PageShortcuts extends StatelessWidget {
  const PageShortcuts({super.key, required this.bindings, required this.child});
  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: bindings,
      child: FocusScope(child: child),
    );
  }
}

/// Rect of a widget in global coordinates, for anchoring popups.
Rect globalRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

bool get isCommandPressed => HardwareKeyboard.instance.isMetaPressed;
bool get isShiftPressed => HardwareKeyboard.instance.isShiftPressed;

/// Rebuilds on every store change.
class StoreBuilder extends StatelessWidget {
  const StoreBuilder({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.store,
      builder: (context, _) => builder(context),
    );
  }
}

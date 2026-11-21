import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import '../../l10n/l10n.dart';

/// Base for menu rows.
sealed class MenuNode<T> {
  const MenuNode();
}

class MenuItemX<T> extends MenuNode<T> {
  const MenuItemX({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.leading,
    this.shortcut,
    this.checked = false,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final T value;
  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final String? shortcut;
  final bool checked;
  final bool destructive;
  final bool enabled;
}

class MenuDivider<T> extends MenuNode<T> {
  const MenuDivider();
}

class MenuHeader<T> extends MenuNode<T> {
  const MenuHeader(this.label);
  final String label;
}

/// Arbitrary content; [builder] receives a close callback that returns a value.
class MenuCustom<T> extends MenuNode<T> {
  const MenuCustom(this.builder);
  final Widget Function(BuildContext context, void Function(T value) close)
  builder;
}

/// Shows a menu at [at] (pointer position) or under [anchor].
Future<T?> showDocketMenu<T>(
  BuildContext context, {
  Offset? at,
  Rect? anchor,
  required List<MenuNode<T>> items,
  double width = 220,
}) {
  final rect = anchor ?? Rect.fromLTWH(at!.dx, at.dy, 0, 0);
  return showAnchored<T>(
    context,
    anchor: rect,
    width: width,
    builder: (context) => _MenuBody<T>(items: items),
  );
}

class _MenuBody<T> extends StatelessWidget {
  const _MenuBody({required this.items});
  final List<MenuNode<T>> items;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    void close(T value) => Navigator.of(context).pop(value);
    final hasChecks = items.any((i) => i is MenuItemX<T> && i.checked);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            switch (item) {
              MenuDivider<T>() => Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 10,
                ),
                child: Container(height: 1, color: p.divider),
              ),
              MenuHeader<T>(:final label) => Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 14, 3),
                child: Text(
                  label,
                  style: Type.captionStrong.copyWith(color: p.textTertiary),
                ),
              ),
              MenuCustom<T>(:final builder) => builder(context, close),
              MenuItemX<T>() => _MenuRow<T>(
                item: item,
                reserveCheck: hasChecks,
                onTap: () => close(item.value),
              ),
            },
        ],
      ),
    );
  }
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.onTap,
    required this.reserveCheck,
  });
  final MenuItemX<T> item;
  final VoidCallback onTap;
  final bool reserveCheck;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      onTap: item.enabled ? onTap : null,
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered, _) {
        final highlight = hovered && item.enabled;
        final fg = !item.enabled
            ? p.textTertiary
            : highlight
            ? Colors.white
            : item.destructive
            ? p.urgent
            : p.text;
        return Container(
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: highlight
                ? (item.destructive ? p.urgent : p.accent)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              if (reserveCheck)
                SizedBox(
                  width: 18,
                  child: item.checked
                      ? Icon(Icons.check_rounded, size: 14, color: fg)
                      : null,
                ),
              if (item.leading != null) ...[
                item.leading!,
                const SizedBox(width: 8),
              ],
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 15,
                  color: highlight ? Colors.white : (item.iconColor ?? fg),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: Type.body.copyWith(color: fg),
                ),
              ),
              if (item.shortcut != null)
                Text(
                  item.shortcut!,
                  style: Type.small.copyWith(
                    color: highlight ? Colors.white70 : p.textTertiary,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A popup card positioned against [anchor] (below it when there is room, else above).
Future<T?> showAnchored<T>(
  BuildContext context, {
  required Rect anchor,
  required WidgetBuilder builder,
  double width = 240,
}) {
  return Navigator.of(
    context,
  ).push<T>(_AnchoredRoute<T>(anchor: anchor, builder: builder, width: width));
}

class _AnchoredRoute<T> extends PopupRoute<T> {
  _AnchoredRoute({
    required this.anchor,
    required this.builder,
    required this.width,
  });
  final Rect anchor;
  final WidgetBuilder builder;
  final double width;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => tr('Dismiss');

  @override
  Duration get transitionDuration => const Duration(milliseconds: 110);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 80);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final p = context.palette;
    return CustomSingleChildLayout(
      delegate: _AnchorLayout(anchor, width, Directionality.of(context)),
      child: Material(
        color: p.raised,
        elevation: 0,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: p.shadow,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(child: Builder(builder: builder)),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: 0.97, end: 1.0).animate(curved),
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

class _AnchorLayout extends SingleChildLayoutDelegate {
  _AnchorLayout(this.anchor, this.width, this.direction);
  final Rect anchor;
  final double width;

  /// Menus open toward the reading direction: rightward in English, leftward in Arabic.
  final TextDirection direction;
  static const margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: 0,
      maxWidth: (constraints.maxWidth - margin * 2).clamp(0, width),
      maxHeight: constraints.maxHeight - margin * 2,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = direction == TextDirection.rtl
        ? anchor.right - childSize.width
        : anchor.left;
    if (x + childSize.width > size.width - margin) {
      x = size.width - margin - childSize.width;
    }
    x = x.clamp(margin, size.width);
    final below = anchor.bottom + 4;
    final above = anchor.top - 4 - childSize.height;
    double y;
    if (below + childSize.height <= size.height - margin) {
      y = below;
    } else if (above >= margin) {
      y = above;
    } else {
      y = (size.height - childSize.height - margin).clamp(margin, size.height);
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_AnchorLayout old) =>
      old.anchor != anchor || old.width != width || old.direction != direction;
}

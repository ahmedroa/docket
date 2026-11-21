import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

class ToastData {
  ToastData(this.id, this.message, this.actionLabel, this.onAction);
  final int id;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// One toast at a time; a new one replaces the old.
class ToastController extends ValueNotifier<ToastData?> {
  ToastController() : super(null);
  Timer? _timer;
  int _counter = 0;

  void show(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    _timer?.cancel();
    value = ToastData(++_counter, message, actionLabel, onAction);
    _timer = Timer(
      duration ?? Duration(seconds: actionLabel == null ? 2 : 5),
      dismiss,
    );
  }

  void dismiss() {
    _timer?.cancel();
    value = null;
  }
}

class ToastHost extends StatelessWidget {
  const ToastHost({super.key, required this.controller});
  final ToastController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ValueListenableBuilder<ToastData?>(
      valueListenable: controller,
      builder: (context, toast, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: toast == null
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey(toast.id),
                  constraints: const BoxConstraints(maxWidth: 340),
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: p.isDark
                        ? const Color(0xFF3A3A3C)
                        : const Color(0xF21C1C1E),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: p.shadow,
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          toast.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Type.small.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (toast.actionLabel != null) ...[
                        const SizedBox(width: 10),
                        _ToastAction(
                          label: toast.actionLabel!,
                          onTap: () {
                            controller.dismiss();
                            toast.onAction?.call();
                          },
                        ),
                      ] else
                        const SizedBox(width: 6),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _ToastAction extends StatefulWidget {
  const _ToastAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_ToastAction> createState() => _ToastActionState();
}

class _ToastActionState extends State<_ToastAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.palette.isDark
        ? const Color(0xFF9DB3FF)
        : const Color(0xFFA8BCFF);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hover
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            style: Type.small.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

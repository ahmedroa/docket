import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'common.dart';
import '../../l10n/l10n.dart';

/// Small centred confirmation card. ↵ confirms, esc cancels.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = false,
  String? cancelLabel,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Cancel'),
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.96,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
    pageBuilder: (context, _, _) => _ConfirmCard(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel ?? tr('Cancel'),
      destructive: destructive,
    ),
  );
  return result ?? false;
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            Navigator.of(context).pop(true),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            Navigator.of(context).pop(true),
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: Material(
            color: p.raised,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 290,
              padding: const EdgeInsetsDirectional.fromSTEB(18, 18, 18, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
                boxShadow: [
                  BoxShadow(
                    color: p.shadow,
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Type.title.copyWith(color: p.text)),
                  if (message != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      message!,
                      style: Type.small.copyWith(color: p.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      DButton(
                        label: cancelLabel,
                        onTap: () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: 8),
                      DButton(
                        label: confirmLabel,
                        kind: destructive
                            ? ButtonKind.danger
                            : ButtonKind.primary,
                        onTap: () => Navigator.of(context).pop(true),
                      ),
                    ],
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

/// Three-way choice (e.g. delete a company: move tasks / delete tasks / cancel).
Future<String?> choiceDialog(
  BuildContext context, {
  required String title,
  String? message,
  required List<(String value, String label, ButtonKind kind)> choices,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Cancel'),
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (context, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (context, _, _) {
      final p = context.palette;
      return Center(
        child: Material(
          color: p.raised,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 300,
            padding: const EdgeInsetsDirectional.fromSTEB(18, 18, 18, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
              boxShadow: [
                BoxShadow(
                  color: p.shadow,
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Type.title.copyWith(color: p.text)),
                if (message != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: Type.small.copyWith(color: p.textSecondary),
                  ),
                ],
                const SizedBox(height: 14),
                for (final (value, label, kind) in choices) ...[
                  DButton(
                    label: label,
                    kind: kind,
                    expand: true,
                    onTap: () => Navigator.of(context).pop(value),
                  ),
                  const SizedBox(height: 6),
                ],
                DButton(
                  label: tr('Cancel'),
                  kind: ButtonKind.ghost,
                  expand: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

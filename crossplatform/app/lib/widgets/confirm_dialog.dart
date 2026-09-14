import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// App-styled confirmation dialog. Returns true only on explicit confirm.
/// [destructive] renders the confirm action in red.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: LText(title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      content: LText(message,
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const LText("Cancel")),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: LText(confirmLabel,
                style: destructive ? const TextStyle(color: Colors.red) : null)),
      ],
    ),
  );
  return ok == true;
}

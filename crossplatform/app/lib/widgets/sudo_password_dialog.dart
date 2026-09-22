import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import '../models/host.dart';

/// Prompts for the sudo password used by elevated SFTP. Pops with
/// `(password:, remember: false)` on OK, or null when cancelled.
/// Credentials are never persisted.
class SudoPasswordDialog extends StatefulWidget {
  final Host host;
  const SudoPasswordDialog({super.key, required this.host});

  @override
  State<SudoPasswordDialog> createState() => _SudoPasswordDialogState();
}

class _SudoPasswordDialogState extends State<SudoPasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    Navigator.of(context)
        .pop((password: _controller.text, remember: false));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const LText("Sudo password"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            LMessage("Root SFTP on {0}@{1} needs the sudo password.", [widget.host.username, widget.host.host]),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            autofillHints: const [],
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            onSubmitted: (_) => _submit(),
            decoration:  InputDecoration(
              labelText: tr(context, "Password"),
              border: OutlineInputBorder(),
            ),
          ),

        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const LText("Cancel")),
        FilledButton(onPressed: _submit, child: const LText("OK")),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:waytty_l10n/waytty_l10n.dart';

import '../models/known_host.dart';

/// Close only this route when its attempt is cancelled or the trust timer ends.
Future<bool> showSshHostKeyDialog(
  BuildContext context,
  HostKeyChallenge challenge,
) async {
  if (challenge.isResolved) return false;
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SshHostKeyDialog(challenge: challenge),
  );
  final shown = navigator.push(route);
  challenge.result.then((_) {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  });
  final accepted = await shown;
  challenge.resolve(accepted == true);
  return challenge.result;
}

/// The same first-trust/mismatch review on desktop and mobile.
class SshHostKeyDialog extends StatefulWidget {
  final HostKeyChallenge challenge;
  const SshHostKeyDialog({super.key, required this.challenge});

  @override
  State<SshHostKeyDialog> createState() => _SshHostKeyDialogState();
}

class _SshHostKeyDialogState extends State<SshHostKeyDialog> {
  bool _verified = false;

  @override
  Widget build(BuildContext context) {
    final challenge = widget.challenge;
    return AlertDialog(
      title: LText(
        challenge.isMismatch ? 'Host key changed' : 'Trust this SSH server?',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('${challenge.host}:${challenge.port}'),
              const SizedBox(height: 12),
              const LText('Key type'),
              SelectableText(challenge.keyType),
              const SizedBox(height: 12),
              const LText('Fingerprint (MD5)'),
              if (challenge.isMismatch) ...[
                const LText('Old'),
                SelectableText(challenge.oldFingerprint!),
                const SizedBox(height: 8),
                const LText('New'),
              ],
              SelectableText(challenge.newFingerprint),
              const SizedBox(height: 12),
              LText(
                challenge.isMismatch
                    ? 'This could indicate a man-in-the-middle attack. Only trust the new key if you know the server key changed.'
                    : 'This server is not yet trusted. Compare this fingerprint with one provided by the server administrator through a trusted channel before connecting.',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _verified,
                onChanged: (value) => setState(() => _verified = value == true),
                title: const LText('I have verified this fingerprint.'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const LText('Cancel'),
        ),
        FilledButton(
          onPressed: _verified ? () => Navigator.of(context).pop(true) : null,
          child: LText(
            challenge.isMismatch ? 'Trust new key' : 'Trust and connect',
          ),
        ),
      ],
    );
  }
}

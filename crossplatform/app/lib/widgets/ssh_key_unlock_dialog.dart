import 'package:flutter/material.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import '../services/local_ssh_key_store.dart';

class SshKeyUnlockDialog extends StatefulWidget {
  final LocalSshKeyStore store;
  const SshKeyUnlockDialog({super.key, required this.store});
  @override
  State<SshKeyUnlockDialog> createState() => _SshKeyUnlockDialogState();
}

class _SshKeyUnlockDialogState extends State<SshKeyUnlockDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final bool _setup = !widget.store.configured;
  bool _busy = false;
  bool _accepted = false;
  String? _error;

  @override
  void dispose() {
    // A dismissed or cancelled in-flight unlock must not unlock the store later.
    if (_busy && !_accepted) widget.store.lock();
    for (final controller in [_password, _confirm]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_setup && _password.text.runes.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (_setup && _password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.unlock(_password.text);
      if (!mounted) return;
      _accepted = true;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Could not unlock saved keys. Check the password and try again.';
        });
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool focus = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      obscureText: true,
      autofocus: focus,
      enabled: !_busy,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: const [],
      decoration: InputDecoration(
        labelText: tr(context, label),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _submit(),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: LText(
      _setup ? 'Protect saved private keys' : 'Unlock saved private keys',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              _setup
                  ? 'Choose a local unlock password. Enter it once after restarting waytty. If you forget it, delete the saved keys and paste them again.'
                  : 'Enter your local unlock password. Saved private keys stay available until you lock them or quit waytty.',
            ),
            _field(_password, 'Local unlock password', focus: true),
            if (_setup) _field(_confirm, 'Confirm unlock password'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const LText('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: LText(_setup ? 'Save' : 'Unlock'),
      ),
    ],
  );
}

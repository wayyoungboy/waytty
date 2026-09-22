import 'package:flutter/material.dart';
import 'package:waytty_l10n/waytty_l10n.dart';

import '../models/host.dart';
import '../models/ssh_credentials.dart';
import '../models/ssh_connection_attempt.dart';
import '../services/local_ssh_key_store.dart';
import '../services/manual_ssh_identity.dart';
import 'ssh_key_unlock_dialog.dart';

/// Serializes user requests so parallel connects do not stack secret dialogs.
class ManualCredentialPrompts {
  final BuildContext? Function() contextForPrompt;
  final LocalSshKeyStore? privateKeys;
  final Future<bool> Function(Host)? canSaveKey;
  Future<void> _tail = Future.value();
  ManualCredentialPrompts(
    this.contextForPrompt, {
    this.privateKeys,
    this.canSaveKey,
  });

  Future<T?> _enqueue<T>(Future<T?> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<T?> show<T>(
    Widget Function() builder, {
    SshConnectionAttempt? attempt,
  }) => _enqueue(() => _showNow<T>(builder, attempt: attempt));

  Future<T?> _showNow<T>(
    Widget Function() builder, {
    SshConnectionAttempt? attempt,
  }) async {
    if (attempt?.isCancelled == true) return null;
    final context = contextForPrompt();
    if (context == null || !context.mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(context: context, builder: (_) => builder());
    void dismiss() {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    }

    final shown = navigator.push(route);
    attempt?.addCancelListener(dismiss);
    try {
      final value = await shown;
      return attempt?.isCancelled == true ? null : value;
    } finally {
      attempt?.removeCancelListener(dismiss);
    }
  }

  Future<bool> _unlock(SshConnectionAttempt? attempt) async {
    final store = privateKeys!;
    if (attempt?.isCancelled == true) return false;
    if (store.unlocked) return true;
    return await _showNow<bool>(
          () => SshKeyUnlockDialog(store: store),
          attempt: attempt,
        ) ==
        true;
  }

  Future<SshCredentials?> request(Host host, [SshConnectionAttempt? attempt]) =>
      _enqueue(() => _request(host, attempt));

  Future<void> replace(Host host) async {
    await _enqueue(() => _request(host, null, savingOnly: true));
  }

  Future<SshCredentials?> _request(
    Host host,
    SshConnectionAttempt? attempt, {
    bool savingOnly = false,
  }) async {
    if (attempt?.isCancelled == true) return null;
    final store = host.authType == AuthType.password ? null : privateKeys;
    // A detached snapshot prevents an edit during a dialog from changing which
    // destination the user authorizes this key for.
    final snapshot = Host.fromJson(host.toJson());
    if (store != null) {
      await store.load();
      if (!savingOnly && store.hasKey(snapshot.id)) {
        if (!await _unlock(attempt)) return null;
        final saved = await store.read(snapshot);
        if (attempt?.isCancelled == true) return null;
        if (saved != null) return saved;
      }
    }
    final allowSave =
        store != null && (await canSaveKey?.call(snapshot) ?? true);
    if (savingOnly && !allowSave) return null;
    final input = await _showNow<SshCredentials>(
      () => SshCredentialsDialog(
        host: snapshot,
        allowSave: allowSave,
        savingOnly: savingOnly,
        validateKey: store != null,
      ),
      attempt: attempt,
    );
    if (input == null || attempt?.isCancelled == true) return null;
    if (store != null && input.savePrivateKey) {
      if (!await _unlock(attempt) || attempt?.isCancelled == true) return null;
      // The connection may have been removed while the prompt was open.
      if (!(await canSaveKey?.call(snapshot) ?? true)) return null;
      await store.save(
        snapshot,
        input,
        cancelled: () => attempt?.isCancelled == true,
      );
      if (attempt?.isCancelled == true) return null;
    }
    return input;
  }

  Future<String?> requestProxy(
    Host host, [
    SshConnectionAttempt? attempt,
  ]) async => (await show<SshCredentials>(
    () => SshCredentialsDialog(host: host, proxy: true),
    attempt: attempt,
  ))?.password;
}

class SshCredentialsDialog extends StatefulWidget {
  final Host host;
  final bool proxy;
  final bool allowSave;
  final bool savingOnly;
  final bool validateKey;
  const SshCredentialsDialog({
    super.key,
    required this.host,
    this.proxy = false,
    this.allowSave = false,
    this.savingOnly = false,
    this.validateKey = false,
  });

  @override
  State<SshCredentialsDialog> createState() => _SshCredentialsDialogState();
}

class _SshCredentialsDialogState extends State<SshCredentialsDialog> {
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _passphrase = TextEditingController();
  final _certificate = TextEditingController();
  bool _remember = true;
  String? _error;
  bool get _passwordOnly =>
      widget.proxy || widget.host.authType == AuthType.password;

  @override
  void dispose() {
    for (final controller in [_password, _key, _passphrase, _certificate]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_passwordOnly && _key.text.trim().isEmpty) return;
    final input = SshCredentials(
      password: _passwordOnly ? _password.text : null,
      privateKey: _passwordOnly ? null : _key.text,
      passphrase: _passwordOnly ? null : _passphrase.text,
      certificate: _passwordOnly ? null : _certificate.text,
      savePrivateKey: !_passwordOnly && widget.allowSave && _remember,
    );
    if (!_passwordOnly && widget.validateKey) {
      try {
        parseManualSshIdentity(widget.host, input);
      } catch (_) {
        setState(
          () => _error = 'Invalid private key, certificate, or passphrase.',
        );
        return;
      }
    }
    Navigator.of(context).pop(input);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    int lines = 1,
    bool autofocus = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      obscureText: secret,
      maxLines: lines,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: const [],
      keyboardType: lines > 1 ? TextInputType.multiline : TextInputType.text,
      decoration: InputDecoration(
        labelText: tr(context, label),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: lines == 1 ? (_) => _submit() : null,
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: LText(
      widget.proxy ? 'Proxy authentication' : 'Manual SSH authentication',
    ),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.proxy
                  ? '${widget.host.proxyUsername}@${widget.host.proxyHost}:${widget.host.proxyPort}'
                  : '${widget.host.label} · ${widget.host.username}@${widget.host.host}:${widget.host.port}',
            ),
            const SizedBox(height: 8),
            LText(
              _passwordOnly
                  ? 'Enter credentials manually. Passwords are not saved to disk.'
                  : 'Paste your private key. Saved keys are encrypted locally and are not included in cloud sync.',
            ),
            if (_passwordOnly)
              _field(_password, 'Password', secret: true, autofocus: true)
            else ...[
              _field(
                _key,
                'Paste private key (PEM / OpenSSH)',
                lines: 5,
                autofocus: true,
              ),
              _field(
                _passphrase,
                'Private key passphrase (optional)',
                secret: true,
              ),
              if (widget.host.authType == AuthType.certificate)
                _field(_certificate, 'Paste SSH certificate', lines: 3),
              if (widget.allowSave)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _remember,
                  onChanged: widget.savingOnly
                      ? null
                      : (v) => setState(() => _remember = v ?? false),
                  title: const LText('Save private key with this connection'),
                )
              else if (widget.validateKey)
                const LText(
                  'Save the connection before saving its private key.',
                ),
              if (_error != null)
                LText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
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
        onPressed: _submit,
        child: LText(widget.savingOnly ? 'Save' : 'Connect'),
      ),
    ],
  );
}

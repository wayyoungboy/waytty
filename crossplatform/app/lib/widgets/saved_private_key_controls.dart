import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import '../models/host.dart';
import '../services/local_ssh_key_store.dart';
import '../services/ssh_service.dart';

/// Management applies to the persisted connection, never unsaved form edits.
class SavedPrivateKeyControls extends StatefulWidget {
  final Host host;
  const SavedPrivateKeyControls({super.key, required this.host});
  @override
  State<SavedPrivateKeyControls> createState() =>
      _SavedPrivateKeyControlsState();
}

class _SavedPrivateKeyControlsState extends State<SavedPrivateKeyControls> {
  late final SshService _ssh = context.read<SshService>();
  late final LocalSshKeyStore _store = _ssh.savedPrivateKeys;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _store.load().then(
      (_) {
        if (mounted) setState(() => _loaded = true);
      },
      onError: (Object _) {
        if (mounted) {
          setState(() => _error = 'Could not load saved private keys.');
        }
      },
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update saved private key.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Delete saved private key?'),
        content: const LText(
          'The connection is kept. You will need to paste its private key again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LText('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _run(() => _store.remove(widget.host.id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) {
      final saved = _store.hasKey(widget.host.id);
      if (_loaded && !saved && widget.host.authType == AuthType.password) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              saved
                  ? 'Private key saved locally (encrypted)'
                  : 'No private key saved for this connection',
            ),
            if (_error != null)
              LText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              children: [
                if (widget.host.authType != AuthType.password)
                  TextButton(
                    onPressed:
                        !_loaded || _busy || _ssh.privateKeyEditor == null
                        ? null
                        : () => _run(() => _ssh.privateKeyEditor!(widget.host)),
                    child: LText(
                      saved ? 'Replace saved private key' : 'Save private key',
                    ),
                  ),
                if (saved)
                  TextButton(
                    onPressed: _busy ? null : _delete,
                    child: const LText('Delete saved private key'),
                  ),
                if (_store.unlocked)
                  TextButton(
                    onPressed: _busy ? null : _store.lock,
                    child: const LText('Lock saved private keys'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

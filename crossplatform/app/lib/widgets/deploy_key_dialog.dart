import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/host.dart';
import '../models/ssh_key.dart';
import '../providers/host_provider.dart';
import '../services/key_gen_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

/// ssh-copy-id-style deploy: pick a saved host, append [entry]'s public
/// key to its ~/.ssh/authorized_keys (idempotent via grep -qxF). Failures
/// keep the dialog open for retry.
class DeployKeyDialog extends StatefulWidget {
  final SshKeyEntry entry;
  const DeployKeyDialog({super.key, required this.entry});

  @override
  State<DeployKeyDialog> createState() => _DeployKeyDialogState();
}

class _DeployKeyDialogState extends State<DeployKeyDialog> {
  String _search = '';
  String? _busyHostId;
  String? _error;

  Future<void> _deploy(Host host) async {
    setState(() {
      _busyHostId = host.id;
      _error = null;
    });
    try {
      final cmd = KeyGenService.buildDeployCommand(widget.entry.publicKey);
      final r = await context.read<SshService>().exec(host, cmd);
      if (!mounted) return;
      if (r.exitCode == 0) {
        final added = r.stdout.contains('ADDED');
        Navigator.pop(context);
        AppSnack.success(
            context,
            added
                ? LMessage('Public key added to {0}', [host.label])
                : LMessage('Key already deployed on {0}', [host.label]));
      } else {
        setState(() => _error = 'Failed on ${host.label}: '
            '${r.stderr.trim().isEmpty ? 'exit ${r.exitCode}' : r.stderr.trim()}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed on ${host.label}: $e');
    } finally {
      if (mounted) setState(() => _busyHostId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final hosts = context
        .watch<HostProvider>()
        .allHosts
        .where((h) =>
            q.isEmpty ||
            h.label.toLowerCase().contains(q) ||
            h.host.toLowerCase().contains(q))
        .toList();

    return AlertDialog(
      backgroundColor: AppColors.card,
      title: LText(LMessage("Deploy \"{0}\" to host", [widget.entry.label]),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      content: SizedBox(
        width: 380,
        height: 360,
        child: Column(children: [
          TextField(
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration:  InputDecoration(
              hintText: tr(context, "Search hosts…"),
              hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              prefixIcon: Icon(Icons.search, size: 16),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.red, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: hosts.isEmpty
                ? const Center(
                    child: LText("No hosts",
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 13)))
                : ListView.builder(
                    itemCount: hosts.length,
                    itemBuilder: (_, i) {
                      final h = hosts[i];
                      final busy = _busyHostId == h.id;
                      return ListTile(
                        dense: true,
                        enabled: _busyHostId == null,
                        leading: const Icon(Icons.dns_outlined,
                            size: 16, color: AppColors.textSecondary),
                        title: Text(h.label,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13)),
                        subtitle: LText(LMessage("{0}@{1}", [h.username, h.host]),
                            style: const TextStyle(
                                color: AppColors.textTertiary, fontSize: 11)),
                        trailing: busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5))
                            : null,
                        onTap: () => _deploy(h),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText("Close")),
      ],
    );
  }
}

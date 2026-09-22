import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/known_host.dart';
import '../../providers/known_hosts_provider.dart';
import '../../widgets/ssh_host_key_dialog.dart';

/// Watches [KnownHostsProvider.pendingChallenge] and shows a single TOFU
/// first-trust or changed-key dialog before SSH authentication.
class TofuWatcher extends StatefulWidget {
  final Widget child;
  const TofuWatcher({super.key, required this.child});

  @override
  State<TofuWatcher> createState() => _TofuWatcherState();
}

class _TofuWatcherState extends State<TofuWatcher> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final challenge = context.watch<KnownHostsProvider>().pendingChallenge;
    if (challenge != null && !challenge.isResolved && !_dialogOpen) {
      _dialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _show(challenge);
        } else {
          challenge.reject(); // never leave the connect future hanging
        }
      });
    }
    return widget.child;
  }

  Future<void> _show(HostKeyChallenge challenge) async {
    await showSshHostKeyDialog(context, challenge);
    if (mounted) setState(() => _dialogOpen = false);
  }
}

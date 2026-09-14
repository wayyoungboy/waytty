import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/firewall_status.dart';
import '../models/host.dart';
import 'ssh_service.dart';

class FirewallStatusService {
  Timer? _timer;
  bool _inFlight = false;
  int _generation = 0;
  final Host host;
  final SshService sshService;
  final void Function(FirewallStatus) onUpdate;
  final void Function(Object error)? onError;

  FirewallStatusService({
    required this.host,
    required this.sshService,
    required this.onUpdate,
    this.onError,
  });

  void start({Duration interval = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => poll());
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  /// Fires one poll cycle immediately. Exposed for tests.
  Future<void> poll() async {
    if (_inFlight) return;
    final generation = _generation;
    _inFlight = true;
    try {
      final result = await sshService.execForMonitoring(host, _kCommand);
      if (generation != _generation) return;
      onUpdate(FirewallStatus.fromShellOutput(result.stdout));
    } catch (e, st) {
      if (generation != _generation) return;
      debugPrint(
        '[FirewallStatusService] poll failed for ${host.host}: $e\n$st',
      );
      onError?.call(e);
    } finally {
      _inFlight = false;
    }
  }
}

const _kCommand =
    'ufw status numbered 2>/dev/null || '
    'iptables-save 2>/dev/null || '
    'nft list ruleset 2>/dev/null || '
    'echo __NO_FIREWALL__';

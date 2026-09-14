import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/host.dart';
import '../models/system_snapshot.dart';
import 'ssh_service.dart';

class SystemStatsService {
  Timer? _timer;
  bool _inFlight = false;
  int _generation = 0;
  final Host host;
  final SshService sshService;
  final void Function(SystemSnapshot) onUpdate;
  final void Function(Object error)? onError;

  SystemStatsService({
    required this.host,
    required this.sshService,
    required this.onUpdate,
    this.onError,
  });

  void start({Duration interval = const Duration(seconds: 5)}) {
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
      final snapshot = SystemSnapshot.fromShellOutput(result.stdout);
      if (!snapshot.cpuAvailable || snapshot.totalMemBytes <= 0) {
        throw const FormatException(
          'Linux /proc system metrics are unavailable',
        );
      }
      onUpdate(snapshot);
    } catch (e, st) {
      if (generation != _generation) return;
      debugPrint('[SystemStatsService] poll failed: $e\n$st');
      onError?.call(e);
    } finally {
      _inFlight = false;
    }
  }
}

// Raw string concatenation — compiled to a single constant.
// The shell reads /proc/stat twice 200ms apart to compute CPU delta in one exec.
const _kCommand =
    r'LC_ALL=C; export LC_ALL; '
    r'c1=$(grep -E "^cpu[0-9]*[[:space:]]" /proc/stat 2>/dev/null); sleep 0.2; '
    r'c2=$(grep -E "^cpu[0-9]*[[:space:]]" /proc/stat 2>/dev/null); '
    r'printf "__CPU1__\n%s\n__CPU2__\n%s\n" "$c1" "$c2"; '
    r'printf "__MEM__\n"; cat /proc/meminfo 2>/dev/null; '
    r'printf "__DISK__\n"; df -Pk 2>/dev/null; '
    r'printf "__UPTIME__\n"; cat /proc/uptime 2>/dev/null; '
    r'printf "__LOAD__\n"; cat /proc/loadavg 2>/dev/null; '
    r'printf "__NET__\n"; cat /proc/net/dev 2>/dev/null; '
    r'printf "__PORTS__\n"; (ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null) | head -201';

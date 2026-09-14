import 'dart:async';
import '../models/host.dart';
import '../models/network_stats.dart';
import 'ssh_service.dart';

class NetworkStatsService {
  Timer? _timer;
  NetworkStats? _previous;
  bool _inFlight = false;
  int _generation = 0;
  final void Function(Object)? onError;
  final void Function(NetworkStatsDelta delta) onUpdate;
  final Host host;
  final SshService sshService;

  NetworkStatsService({
    required this.host,
    required this.sshService,
    required this.onUpdate,
    this.onError,
  });

  void start({Duration interval = const Duration(seconds: 2)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  void stop() {
    _generation++;
    _previous = null;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_inFlight) return;
    _inFlight = true;
    final generation = _generation;
    try {
      final result = await sshService.execForMonitoring(
        host,
        'cat /proc/net/dev 2>/dev/null',
      );
      if (generation != _generation) return;
      final output = result.stdout;
      if (output.isEmpty) {
        throw const FormatException('Network counters unavailable');
      }
      final iface = detectPrimaryInterface(output);
      if (iface == null) return;
      final current = NetworkStats.fromProcNetDev(output, interface: iface);
      if (_previous != null) {
        onUpdate(current.delta(_previous!));
      }
      _previous = current;
    } catch (error) {
      if (generation == _generation) {
        _previous = null;
        onError?.call(error);
      }
    } finally {
      _inFlight = false;
    }
  }

  static String? detectPrimaryInterface(String procNetDevOutput) {
    for (final line in procNetDevOutput.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('Inter') ||
          trimmed.startsWith('face')) {
        continue;
      }
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx < 0) continue;
      final name = trimmed.substring(0, colonIdx).trim();
      if (name == 'lo') continue;
      return name;
    }
    return null;
  }
}

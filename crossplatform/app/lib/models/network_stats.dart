class NetworkStats {
  final String interface;
  final int rxBytes;
  final int txBytes;
  final DateTime timestamp;

  const NetworkStats({
    required this.interface,
    required this.rxBytes,
    required this.txBytes,
    required this.timestamp,
  });

  /// Splits a `/proc/net/dev` data line into `(iface, counters)`.
  ///
  /// The colon that separates counters is the one followed by whitespace and a
  /// digit, so aliases like `eth0:0` keep `:0` in the name instead of being
  /// mistaken for `eth0` with a bogus leading counter field.
  static (String, List<String>)? parseProcNetDevLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'^(.+?):\s+(\d.*)$').firstMatch(trimmed);
    if (match == null) return null;
    final name = match.group(1)!.trim();
    if (name.isEmpty) return null;
    return (name, match.group(2)!.trim().split(RegExp(r'\s+')));
  }

  factory NetworkStats.fromProcNetDev(String output, {required String interface}) {
    for (final line in output.split('\n')) {
      final parsed = parseProcNetDevLine(line);
      if (parsed == null) continue;
      final (name, parts) = parsed;
      if (name != interface || parts.length < 9) continue;
      return NetworkStats(
        interface: interface,
        rxBytes: int.tryParse(parts[0]) ?? 0,
        txBytes: int.tryParse(parts[8]) ?? 0,
        timestamp: DateTime.now(),
      );
    }
    return NetworkStats(interface: interface, rxBytes: 0, txBytes: 0, timestamp: DateTime.now());
  }

  NetworkStatsDelta delta(NetworkStats previous) {
    final seconds = timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
    if (seconds <= 0) return NetworkStatsDelta(rxBytesPerSec: 0, txBytesPerSec: 0);
    return NetworkStatsDelta(
      rxBytesPerSec: ((rxBytes - previous.rxBytes) / seconds).round().clamp(0, double.maxFinite.toInt()),
      txBytesPerSec: ((txBytes - previous.txBytes) / seconds).round().clamp(0, double.maxFinite.toInt()),
    );
  }

  static String formatBytes(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

class NetworkStatsDelta {
  final int rxBytesPerSec;
  final int txBytesPerSec;
  const NetworkStatsDelta({required this.rxBytesPerSec, required this.txBytesPerSec});
}

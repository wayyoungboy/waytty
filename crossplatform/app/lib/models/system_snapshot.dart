import 'network_stats.dart';

class SystemSnapshot {
  final double cpuPercent;

  /// Linux logical CPU IDs. Null means no valid delta (new/reset/stalled core).
  final Map<int, double?> cpuCorePercent;
  final int totalMemBytes;
  final int usedMemBytes;
  final List<DiskMount> disks;
  final Duration uptime;
  final List<PortEntry> ports;
  final DateTime timestamp;
  final bool cpuAvailable;
  final int totalSwapBytes;
  final int usedSwapBytes;
  final List<double> loadAverages;
  final List<NetworkStats> network;

  const SystemSnapshot({
    required this.cpuPercent,
    required this.totalMemBytes,
    required this.usedMemBytes,
    required this.disks,
    required this.uptime,
    required this.ports,
    required this.timestamp,
    this.cpuAvailable = true,
    this.cpuCorePercent = const {},
    this.totalSwapBytes = 0,
    this.usedSwapBytes = 0,
    this.loadAverages = const [],
    this.network = const [],
  });

  factory SystemSnapshot.fromShellOutput(String output) {
    final sections = _splitSections(output);
    final mem = _parseMem(sections['__MEM__'] ?? '');
    final timestamp = DateTime.now();
    final swap = _parseSwap(sections['__MEM__'] ?? '');
    final cpuBefore = _parseCpuRows(sections['__CPU1__'] ?? '');
    final cpuAfter = _parseCpuRows(sections['__CPU2__'] ?? '');
    final coreIds =
        cpuAfter.keys
            .where((name) => name != 'cpu')
            .map((name) => int.parse(name.substring(3)))
            .toList()
          ..sort();
    return SystemSnapshot(
      cpuPercent: _cpuPercent(cpuBefore['cpu'], cpuAfter['cpu']) ?? 0.0,
      cpuCorePercent: Map.unmodifiable({
        for (final id in coreIds)
          id: _cpuPercent(cpuBefore['cpu$id'], cpuAfter['cpu$id']),
      }),
      totalMemBytes: mem.$1,
      usedMemBytes: mem.$2,
      disks: _parseDisks(sections['__DISK__'] ?? ''),
      uptime: _parseUptime(sections['__UPTIME__'] ?? ''),
      ports: _parsePorts(sections['__PORTS__'] ?? ''),
      timestamp: timestamp,
      cpuAvailable: cpuBefore.containsKey('cpu') && cpuAfter.containsKey('cpu'),
      totalSwapBytes: swap.$1,
      usedSwapBytes: swap.$2,
      loadAverages: (sections['__LOAD__'] ?? '')
          .trim()
          .split(RegExp(r'\s+'))
          .take(3)
          .map(double.tryParse)
          .whereType<double>()
          .where((n) => n.isFinite && n >= 0)
          .toList(),
      network: _parseNetwork(sections['__NET__'] ?? '', timestamp),
    );
  }

  static Map<String, String> _splitSections(String output) {
    const sentinels = {
      '__CPU1__',
      '__CPU2__',
      '__MEM__',
      '__DISK__',
      '__UPTIME__',
      '__PORTS__',
      '__LOAD__',
      '__NET__',
    };
    final sections = <String, String>{};
    String? currentKey;
    final buf = StringBuffer();
    for (final line in output.split('\n')) {
      final t = line.trim();
      if (sentinels.contains(t)) {
        if (currentKey != null) sections[currentKey] = buf.toString();
        currentKey = t;
        buf.clear();
      } else if (currentKey != null) {
        buf.writeln(line);
      }
    }
    if (currentKey != null) sections[currentKey] = buf.toString();
    return sections;
  }

  static double? _cpuPercent(List<int>? s1, List<int>? s2) {
    if (s1 == null || s2 == null || s1.length != s2.length) return null;
    for (var i = 0; i < s1.length; i++) {
      if (s2[i] < s1[i]) return null;
    }
    final total1 = s1.reduce((a, b) => a + b);
    final idle1 = s1[3] + s1[4]; // idle + iowait
    final total2 = s2.reduce((a, b) => a + b);
    final idle2 = s2[3] + s2[4];
    final dTotal = total2 - total1;
    final dIdle = idle2 - idle1;
    if (dTotal <= 0) return null;
    return ((1.0 - dIdle / dTotal) * 100.0).clamp(0.0, 100.0);
  }

  static Map<String, List<int>> _parseCpuRows(String section) {
    final rows = <String, List<int>>{};
    for (final line in section.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 6 || !RegExp(r'^cpu[0-9]*$').hasMatch(parts[0])) {
        continue;
      }
      var name = parts[0];
      if (name != 'cpu') {
        final id = int.tryParse(name.substring(3));
        if (id == null) continue;
        name = 'cpu$id';
      }
      // guest/guest_nice are already included in user/nice on Linux.
      final values = parts.skip(1).take(8).map(int.tryParse).toList();
      if (values.any((v) => v == null || v < 0)) continue;
      rows[name] = values.cast<int>();
    }
    return rows;
  }

  static (int, int) _parseSwap(String section) {
    final total = RegExp(
      r'^SwapTotal:\s+(\d+)',
      multiLine: true,
    ).firstMatch(section);
    final free = RegExp(
      r'^SwapFree:\s+(\d+)',
      multiLine: true,
    ).firstMatch(section);
    final totalKb = int.tryParse(total?.group(1) ?? '') ?? 0;
    final freeKb = int.tryParse(free?.group(1) ?? '') ?? 0;
    return (totalKb * 1024, (totalKb - freeKb).clamp(0, totalKb) * 1024);
  }

  static List<NetworkStats> _parseNetwork(String section, DateTime timestamp) {
    final result = <NetworkStats>[];
    for (final line in section.split('\n')) {
      final parsed = NetworkStats.parseProcNetDevLine(line);
      if (parsed == null) continue;
      final (name, counters) = parsed;
      if (name.isEmpty || name == 'lo' || counters.length < 16) continue;
      final rx = int.tryParse(counters[0]);
      final tx = int.tryParse(counters[8]);
      if (rx == null || tx == null || rx < 0 || tx < 0) continue;
      result.add(
        NetworkStats(
          interface: name,
          rxBytes: rx,
          txBytes: tx,
          timestamp: timestamp,
        ),
      );
    }
    return result;
  }

  static (int, int) _parseMem(String section) {
    int totalKb = 0, availableKb = 0;
    for (final line in section.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final val = int.tryParse(parts[1]) ?? 0;
      if (parts[0] == 'MemTotal:') totalKb = val;
      if (parts[0] == 'MemAvailable:') availableKb = val;
    }
    final total = totalKb * 1024;
    final used = ((totalKb - availableKb) * 1024).clamp(0, total);
    return (total, used);
  }

  static const _kSkipFs = {
    'tmpfs',
    'devtmpfs',
    'overlay',
    'squashfs',
    'udev',
    'run',
    'none',
  };

  static List<DiskMount> _parseDisks(String section) {
    final result = <DiskMount>[];
    final lines = section.split('\n').skip(1); // skip header
    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 6) continue;
      final source = parts[0];
      // Exact match only: startsWith("run") previously hid real mounts whose
      // device names began with a skip token (e.g. runtime, run0, nonexistent).
      if (_kSkipFs.contains(source)) continue;
      final totalKb = int.tryParse(parts[1]) ?? 0;
      final usedKb = int.tryParse(parts[2]) ?? 0;
      final mount = parts.skip(5).join(' ');
      result.add(
        DiskMount(
          source: source,
          mountPoint: mount,
          totalKb: totalKb,
          usedKb: usedKb,
        ),
      );
    }
    return result;
  }

  static Duration _parseUptime(String section) {
    final line = section.trim().split('\n').first.trim();
    final secs = double.tryParse(line.split(' ').first) ?? 0.0;
    return Duration(seconds: secs.floor());
  }

  static List<PortEntry> _parsePorts(String section) {
    final entries = <PortEntry>[];
    for (final line in section.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 5) continue;
      final proto = parts[0].toLowerCase();
      if (!proto.startsWith('tcp') && !proto.startsWith('udp')) continue;

      String? localAddr;
      String? processStr;

      // ss format: State is parts[1] (LISTEN/UNCONN), local addr is parts[4]
      if (parts[1] == 'LISTEN' || parts[1] == 'UNCONN') {
        localAddr = parts[4];
        processStr = parts.length > 6 ? parts.skip(6).join(' ') : null;
      }
      // netstat format: State is parts[5], local addr is parts[3]
      else if (parts.length >= 6 && parts[5] == 'LISTEN') {
        localAddr = parts[3];
        processStr = parts.length > 6 ? parts[6] : null;
      }

      if (localAddr == null) continue;
      final lastColon = localAddr.lastIndexOf(':');
      if (lastColon < 0) continue;
      final port = int.tryParse(localAddr.substring(lastColon + 1));
      if (port == null) continue;

      entries.add(
        PortEntry(
          protocol: proto.replaceAll('6', '').replaceAll('4', ''),
          localAddress: localAddr.substring(0, lastColon),
          localPort: port,
          process: _extractProcess(processStr),
        ),
      );
    }

    // Deduplicate by port number, sort ascending
    final seen = <String>{};
    return entries
        .where((e) => seen.add('${e.protocol}:${e.localPort}'))
        .toList()
      ..sort((a, b) => a.localPort.compareTo(b.localPort));
  }

  static String? _extractProcess(String? raw) {
    if (raw == null) return null;
    // ss: users:(("sshd",pid=1234,fd=3))
    final ssMatch = RegExp(r'"([^"]+)"').firstMatch(raw);
    if (ssMatch != null) return ssMatch.group(1);
    // netstat: 1234/sshd
    final parts = raw.split('/');
    return parts.length > 1 ? parts.last.trim() : null;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String formatUptime(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    parts.add('${minutes}m');
    return parts.join(' ');
  }
}

class DiskMount {
  final String source;
  final String mountPoint;
  final int totalKb;
  final int usedKb;

  const DiskMount({
    required this.source,
    required this.mountPoint,
    required this.totalKb,
    required this.usedKb,
  });

  double get usedPercent =>
      totalKb <= 0 ? 0.0 : (usedKb / totalKb).clamp(0.0, 1.0);
}

class PortEntry {
  final String protocol;
  final String localAddress;
  final int localPort;
  final String? process;

  const PortEntry({
    required this.protocol,
    required this.localAddress,
    required this.localPort,
    this.process,
  });
}

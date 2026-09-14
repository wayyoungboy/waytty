import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:provider/provider.dart';
import '../models/firewall_status.dart';
import '../models/host.dart';
import '../models/network_stats.dart';
import '../models/ssh_session.dart';
import '../models/system_snapshot.dart';
import '../providers/session_provider.dart';
import '../services/firewall_status_service.dart';
import '../services/ssh_service.dart';
import '../services/system_stats_service.dart';
import '../theme/app_theme.dart';
import 'cpu_monitor_section.dart';

class ServerMonitorSheet extends StatefulWidget {
  final Host host;
  // Bypasses the SessionProvider check in tests — null means use the real check.
  @visibleForTesting
  final bool? testIsConnected;
  final bool embedded;

  const ServerMonitorSheet({
    super.key,
    required this.host,
    this.testIsConnected,
    this.embedded = false,
  });

  static void show(BuildContext context, Host host) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServerMonitorSheet(host: host),
    );
  }

  @override
  State<ServerMonitorSheet> createState() => ServerMonitorSheetState();
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  const _TrendPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = const Color(0xFF303030)
        ..strokeWidth = 1,
    );
    if (values.length < 2) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - values[i].clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values);
}

// Public so widget tests can cast via tester.state<ServerMonitorSheetState>().
class ServerMonitorSheetState extends State<ServerMonitorSheet> {
  SystemStatsService? _statsService;
  FirewallStatusService? _firewallService;
  SystemSnapshot? _snapshot;
  FirewallStatus? _firewall;
  String? _statsError;
  String? _firewallError;
  bool _connected = false;
  bool _paused = false;
  final _history = <SystemSnapshot>[];
  final _rates = <String, NetworkStatsDelta>{};

  @visibleForTesting
  void debugSetSnapshot(SystemSnapshot s) => setState(() => _snapshot = s);

  @visibleForTesting
  void debugSetFirewall(FirewallStatus f) => setState(() => _firewall = f);

  bool _isConnected(BuildContext context, {bool listen = true}) =>
      widget.testIsConnected ??
      (listen
              ? context.watch<SessionProvider>()
              : context.read<SessionProvider>())
          .sshSessions
          .any(
            (s) =>
                s.host.id == widget.host.id &&
                !s.isWatch &&
                s.status == SessionStatus.connected,
          );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncConnection(_isConnected(context));
  }

  @override
  void didUpdateWidget(covariant ServerMonitorSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host.id != widget.host.id) {
      _syncConnection(false);
      _syncConnection(_isConnected(context, listen: false));
    }
  }

  void _syncConnection(bool connected) {
    if (_connected == connected) return;
    _connected = connected;
    _stopServices();
    _snapshot = null;
    _firewall = null;
    _statsError = null;
    _firewallError = null;
    _rates.clear();
    _history.clear();
    if (connected && !_paused) _startServices();
  }

  void _stopServices() {
    _statsService?.stop();
    _firewallService?.stop();
  }

  void _startServices() {
    _stopServices();
    if (!_connected || _paused) return;
    final ssh = context.read<SshService>();
    _statsService = SystemStatsService(
      host: widget.host,
      sshService: ssh,
      onUpdate: (s) {
        if (!mounted) return;
        setState(() {
          _rates.clear();
          final previous = _snapshot;
          if (previous != null && s.uptime > previous.uptime) {
            for (final net in s.network) {
              final last = previous.network
                  .where((n) => n.interface == net.interface)
                  .firstOrNull;
              if (last != null &&
                  net.rxBytes >= last.rxBytes &&
                  net.txBytes >= last.txBytes) {
                final seconds =
                    (s.uptime - previous.uptime).inMilliseconds / 1000;
                _rates[net.interface] = NetworkStatsDelta(
                  rxBytesPerSec: ((net.rxBytes - last.rxBytes) / seconds)
                      .round(),
                  txBytesPerSec: ((net.txBytes - last.txBytes) / seconds)
                      .round(),
                );
              }
            }
          }
          _snapshot = s;
          _statsError = null;
          _history.add(s);
          if (_history.length > 60) _history.removeAt(0);
        });
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _statsError = e is FormatException
                ? 'Monitoring requires a Linux host with /proc access'
                : e.toString();
            _rates.clear();
          });
        }
      },
    );
    _firewallService = FirewallStatusService(
      host: widget.host,
      sshService: ssh,
      onUpdate: (f) {
        if (mounted) {
          setState(() {
            _firewall = f;
            _firewallError = null;
          });
        }
      },
      onError: (e) {
        if (mounted) setState(() => _firewallError = e.toString());
      },
    );
    _statsService!.start();
    _firewallService!.start();
    // Deliver first reading immediately rather than waiting for the first tick.
    _statsService!.poll();
    _firewallService!.poll();
  }

  @override
  void dispose() {
    _stopServices();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        children: [
          const SizedBox(height: 10),
          _header(),
          Expanded(child: _connected ? _body(null) : _notConnected()),
        ],
      );
    }
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
        ),
        child: Column(
          children: [
            _handle(),
            _header(),
            Expanded(child: _connected ? _body(ctrl) : _notConnected()),
          ],
        ),
      ),
    );
  }

  Widget _handle() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3A),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            widget.host.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (_connected) ...[
          LText(
            _paused
                ? 'Paused'
                : _statsError != null
                ? 'Update failed'
                : _snapshot == null
                ? 'Loading…'
                : 'Live',
            style: TextStyle(
              color: _paused || _statsError != null
                  ? AppColors.textSecondary
                  : AppColors.accent,
              fontSize: 11,
            ),
          ),
          IconButton(
            tooltip: tr(
              context,
              _paused ? 'Resume monitoring' : 'Pause monitoring',
            ),
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 17),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
              _paused = !_paused;
              if (_paused) {
                _stopServices();
              } else {
                _startServices();
              }
            }),
          ),
          IconButton(
            tooltip: tr(context, 'Refresh'),
            icon: const Icon(Icons.refresh, size: 17),
            visualDensity: VisualDensity.compact,
            onPressed: _paused
                ? null
                : () {
                    _statsService?.poll();
                    _firewallService?.poll();
                  },
          ),
        ],
      ],
    ),
  );

  Widget _notConnected() => const Center(
    child: LText(
      "No active session — open a terminal first",
      style: TextStyle(color: AppColors.textSecondary),
    ),
  );

  Widget _body(ScrollController? ctrl) => ListView(
    controller: ctrl,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    children: [
      _sectionTitle('SYSTEM'),
      if (_statsError != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LText(
            _statsError == 'Monitoring requires a Linux host with /proc access'
                ? _statsError!
                : LMessage("Failed to load stats: {0}", [_statsError]),
            style: TextStyle(color: Colors.red.shade300, fontSize: 12),
          ),
        ),
      if (_snapshot == null && _statsError == null)
        const Center(child: CircularProgressIndicator())
      else if (_snapshot != null)
        _systemSection(_snapshot!),
      if (_snapshot != null) ...[
        const SizedBox(height: 16),
        _sectionTitle('Network'),
        _networkSection(_snapshot!),
      ],
      const SizedBox(height: 16),
      _sectionTitle('PORTS'),
      if (_statsError != null && _snapshot == null)
        const SizedBox.shrink()
      else if (_snapshot == null)
        const Center(child: CircularProgressIndicator())
      else
        _portsSection(_snapshot!.ports),
      const SizedBox(height: 16),
      _sectionTitle('FIREWALL'),
      if (_firewallError != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LText(
            LMessage("Failed to load firewall: {0}", [_firewallError]),
            style: TextStyle(color: Colors.red.shade300, fontSize: 12),
          ),
        ),
      if (_firewall == null && _firewallError == null)
        const Center(child: CircularProgressIndicator())
      else if (_firewall != null)
        _firewallSection(_firewall!),
    ],
  );

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: LText(
      t,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _systemSection(SystemSnapshot s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LText(
        LMessage('Updated {0} · every 5 seconds', [
          '${s.timestamp.hour.toString().padLeft(2, '0')}:${s.timestamp.minute.toString().padLeft(2, '0')}:${s.timestamp.second.toString().padLeft(2, '0')}',
        ]),
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
      ),
      const SizedBox(height: 8),
      _statRow('Uptime', SystemSnapshot.formatUptime(s.uptime)),
      if (s.loadAverages.length == 3) ...[
        const SizedBox(height: 6),
        _statRow(
          'Load (1/5/15m)',
          s.loadAverages.map((n) => n.toStringAsFixed(2)).join(' / '),
        ),
      ],
      const SizedBox(height: 6),
      CpuMonitorSection(snapshot: s, history: _history),
      const SizedBox(height: 6),
      _barRow(
        'Memory',
        s.totalMemBytes == 0 ? 0 : s.usedMemBytes / s.totalMemBytes,
        '${SystemSnapshot.formatBytes(s.usedMemBytes)} / '
            '${SystemSnapshot.formatBytes(s.totalMemBytes)}',
      ),
      _trend(
        _history
            .map(
              (s) =>
                  s.totalMemBytes == 0 ? 0.0 : s.usedMemBytes / s.totalMemBytes,
            )
            .toList(),
      ),
      if (s.totalSwapBytes > 0) ...[
        const SizedBox(height: 6),
        _barRow(
          'Swap',
          s.usedSwapBytes / s.totalSwapBytes,
          '${SystemSnapshot.formatBytes(s.usedSwapBytes)} / ${SystemSnapshot.formatBytes(s.totalSwapBytes)}',
        ),
      ],
      ...s.disks.map(
        (d) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _barRow(
            d.mountPoint,
            d.usedPercent,
            '${(d.usedPercent * 100).toStringAsFixed(0)}% · ${SystemSnapshot.formatBytes(d.usedKb * 1024)} / ${SystemSnapshot.formatBytes(d.totalKb * 1024)}',
            rawLabel: true,
          ),
        ),
      ),
    ],
  );

  Widget _statRow(String label, String value) => Row(
    children: [
      SizedBox(
        width: 110,
        child: LText(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  Widget _barRow(
    String label,
    double fraction,
    String right, {
    bool rawLabel = false,
  }) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: rawLabel
                ? Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  )
                : LText(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 3,
            child: Text(
              right,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          minHeight: 6,
          backgroundColor: const Color(0xFF2A2A2A),
          color: fraction > 0.85 ? AppColors.red : AppColors.accent,
        ),
      ),
    ],
  );

  Widget _trend(List<double> values) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: SizedBox(
      height: 32,
      width: double.infinity,
      child: CustomPaint(painter: _TrendPainter(values)),
    ),
  );

  Widget _networkSection(SystemSnapshot snapshot) {
    if (snapshot.network.isEmpty) {
      return const LText(
        'Network counters unavailable',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LText(
          'Per-interface traffic · virtual interfaces shown separately',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
        for (final network in snapshot.network) ...[
          const SizedBox(height: 8),
          Text(
            network.interface,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          ),
          const SizedBox(height: 3),
          if (_rates[network.interface] case final rate?)
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                LText(
                  LMessage('↓ Receive {0}', [
                    NetworkStats.formatBytes(rate.rxBytesPerSec),
                  ]),
                  style: const TextStyle(color: AppColors.accent, fontSize: 11),
                ),
                LText(
                  LMessage('↑ Send {0}', [
                    NetworkStats.formatBytes(rate.txBytesPerSec),
                  ]),
                  style: const TextStyle(
                    color: Color(0xFF60A5FA),
                    fontSize: 11,
                  ),
                ),
              ],
            )
          else
            const LText(
              'Waiting for next sample',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
        ],
      ],
    );
  }

  Widget _portsSection(List<PortEntry> ports) {
    if (ports.isEmpty) {
      return const LText(
        "No listening ports detected",
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    return Column(
      children: ports
          .map(
            (p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      p.protocol,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: LText(
                      LMessage(":{0}", [p.localPort]),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p.process ?? '—',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _firewallSection(FirewallStatus fw) {
    if (fw.type == FirewallType.none) {
      return const LText(
        "No firewall detected",
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _chip(fw.type.name, AppColors.accent),
            const SizedBox(width: 6),
            _chip(
              fw.enabled ? 'active' : 'inactive',
              fw.enabled ? AppColors.accent : AppColors.red,
            ),
            if (fw.defaultInboundPolicy != null) ...[
              const SizedBox(width: 8),
              LText(
                LMessage("default inbound: {0}", [fw.defaultInboundPolicy]),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        if (fw.rules.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...fw.rules.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                r.description,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: LText(label, style: TextStyle(color: color, fontSize: 11)),
  );
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/widgets/broadcast_toolbar.dart';
import 'package:yourssh/widgets/terminal_monitor_panel.dart';
import 'package:yourssh/widgets/server_monitor_sheet.dart';
import 'package:yourssh/widgets/keep_alive_offstage.dart';

typedef _Result = ({String stdout, String stderr, int exitCode});

class _Sessions extends ChangeNotifier implements SessionProvider {
  AppSession? active;
  final all = <AppSession>[];
  @override
  AppSession? get activeSession => active;
  @override
  List<SshSession> get sshSessions =>
      all.whereType<SshSession>().toList();
  void select(AppSession? value) {
    if (value != null && !all.contains(value)) all.add(value);
    active = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ssh extends Fake implements SshService {
  final calls = <String>[];
  bool fail = false;
  int samples = 0;
  Completer<_Result>? pending;
  @override
  Future<_Result> execForMonitoring(Host host, String command) async {
    calls.add(host.id);
    if (command.contains('ufw')) {
      return (stdout: '__NO_FIREWALL__', stderr: '', exitCode: 0);
    }
    if (pending != null) return pending!.future;
    if (fail) throw StateError('fixture unavailable');
    return (
      stdout: _sample(host.id == 'b' ? 20 : 50, sample: ++samples),
      stderr: '',
      exitCode: 0,
    );
  }
}

String _sample(int busy, {int sample = 1}) =>
    '''
__CPU1__
cpu 100 0 0 900 0 0 0 0 0 0
${List.generate(8, (id) => 'cpu$id 100 0 0 900 0 0 0 0 0 0').join('\n')}
__CPU2__
cpu ${100 + busy} 0 0 ${1000 - busy} 0 0 0 0 0 0
${List.generate(8, (id) {
  final coreBusy = (busy + id * 8 - 28).clamp(0, 100);
  return 'cpu$id ${100 + coreBusy} 0 0 ${1000 - coreBusy} 0 0 0 0 0 0';
}).join('\n')}
__MEM__
MemTotal: 8192000 kB
MemAvailable: 4096000 kB
SwapTotal: 1024000 kB
SwapFree: 512000 kB
__UPTIME__
${3600 + sample * 5}.0 0.0
__LOAD__
0.25 0.50 0.75 1/100 200
__NET__
eth0: ${sample * 1024} 0 0 0 0 0 0 0 ${sample * 2048} 0 0 0 0 0 0 0
__DISK__
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/sda1 100000 50000 50000 50% /
__PORTS__
tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=1,fd=3))
''';

SshSession _session(String id) => SshSession(
  host: Host(
    id: id,
    label: 'Settings-$id-very-long-host-name',
    host: '$id.invalid',
    port: 22,
    username: 'fixture',
  ),
  status: SessionStatus.connected,
);

void main() {
  late _Sessions sessions;
  late _Ssh ssh;
  late TerminalLayoutProvider layout;
  setUp(() {
    sessions = _Sessions();
    ssh = _Ssh();
    layout = TerminalLayoutProvider();
  });

  Widget app({
    Locale locale = const Locale('zh'),
    double width = 340,
    bool toolbar = false,
    bool visible = true,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionProvider>.value(value: sessions),
      ChangeNotifierProvider.value(value: layout),
      ChangeNotifierProvider(create: (_) => PluginProvider(plugins: [])),
      Provider<SshService>.value(value: ssh),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      locale: locale,
      supportedLocales: WayttyStrings.supportedLocales,
      localizationsDelegates: WayttyStrings.delegates,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: toolbar
                ? Consumer<TerminalLayoutProvider>(
                    builder: (_, value, _) => Column(
                      children: [
                        const BroadcastToolbar(),
                        if (value.monitorPanelVisible)
                          const Expanded(child: TerminalMonitorPanel()),
                      ],
                    ),
                  )
                : KeepAliveOffstage(
                    active: visible,
                    child: const RepaintBoundary(
                      key: ValueKey('monitor-preview'),
                      child: TerminalMonitorPanel(),
                    ),
                  ),
          ),
        ),
      ),
    ),
  );

  testWidgets('tab switch retains readings and CPU view without new probes', (tester) async {
    final a = _session('a');
    final b = _session('b');
    sessions.select(a);
    await tester.pumpWidget(app());
    await tester.pump();
    final state = tester.state(find.byType(ServerMonitorSheet));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('核心 1').last);
    await tester.pumpAndSettle();
    sessions.select(b);
    await tester.pump();
    await tester.pump();
    final calls = ssh.calls.length;
    sessions.select(a);
    await tester.pump();
    expect(tester.state(find.byType(ServerMonitorSheet)), same(state));
    expect(find.text('30.0%'), findsOneWidget);
    expect(ssh.calls.length, calls);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(ssh.calls.skip(calls), ['a']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hidden monitor pauses polling and restores its last reading', (tester) async {
    sessions.select(_session('a'));
    await tester.pumpWidget(app());
    await tester.pump();
    final state = tester.state(find.byType(ServerMonitorSheet));
    final calls = ssh.calls.length;
    await tester.pumpWidget(app(visible: false));
    await tester.pump(const Duration(seconds: 31));
    expect(ssh.calls.length, calls);
    await tester.pumpWidget(app());
    expect(tester.state(find.byType(ServerMonitorSheet)), same(state));
    expect(find.text('50.0%'), findsWidgets);
    expect(ssh.calls.length, calls);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching back during the first sample reuses the in-flight probe', (tester) async {
    final a = _session('a');
    sessions.select(a);
    final pending = Completer<_Result>();
    ssh.pending = pending;
    await tester.pumpWidget(app());
    await tester.pump();
    ssh.pending = null;
    sessions.select(_session('b'));
    await tester.pump();
    await tester.pump();
    sessions.select(a);
    await tester.pump();
    expect(ssh.calls.where((id) => id == 'a'), hasLength(2),
        reason: 'one metrics probe and one firewall probe, even while pending');
    pending.complete((stdout: _sample(90), stderr: '', exitCode: 0));
    await tester.pump();
    expect(find.text('90.0%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pause survives switching and closed sessions release their monitor', (tester) async {
    final a = _session('a');
    final b = _session('b');
    sessions.select(a);
    await tester.pumpWidget(app());
    await tester.pump();
    final state = tester.state(find.byType(ServerMonitorSheet));
    await tester.tap(find.byTooltip('暂停监控'));
    await tester.pump();
    sessions.select(b);
    await tester.pump();
    await tester.pump();
    final calls = ssh.calls.length;
    sessions.select(a);
    await tester.pump();
    expect(find.byTooltip('继续监控'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    expect(ssh.calls.length, calls);
    sessions.select(b);
    sessions.all.remove(a);
    sessions.notifyListeners();
    await tester.pump();
    expect(state.mounted, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('another connection to the same host cannot keep a disconnected session polling', (tester) async {
    final a = _session('a');
    final b = _session('a');
    sessions.all.add(b);
    sessions.select(a);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(ssh.calls.length, 2, reason: 'unvisited session stays lazy');
    a.status = SessionStatus.disconnected;
    sessions.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(ssh.calls.length, 2);
    expect(find.text('50.0%'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'network rates use elapsed remote sampling time and render in a compact panel',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preview = Platform.environment['WAYTTY_MONITOR_PREVIEW'];
      if (preview != null) {
        await tester.runAsync(() async {
          final cjk = Platform.environment['WAYTTY_MONITOR_CJK_FONT'];
          for (final font in {
            'SF Pro Display': cjk ?? '/System/Library/Fonts/SFNS.ttf',
            'monospace': '/System/Library/Fonts/SFNSMono.ttf',
            'MaterialIcons': 'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          }.entries) {
            final loader = FontLoader(font.key)
              ..addFont(File(font.value).readAsBytes().then((b) => ByteData.sublistView(b)));
            await loader.load();
          }
        });
      }
      sessions.select(_session('a'));
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('等待下一次采样'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('↓ 接收 205 B/s'), findsOneWidget);
      expect(find.text('↑ 发送 410 B/s'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (preview != null) {
        final cpuView = Platform.environment['WAYTTY_MONITOR_CPU_VIEW'];
        if (cpuView != null) {
          await tester.tap(find.byType(DropdownButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text(cpuView).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('monitor-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(preview).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('CPU view switches use already collected readings without extra SSH probes', (tester) async {
    sessions.select(_session('a'));
    await tester.pumpWidget(app());
    await tester.pump();
    final count = ssh.calls.length;
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部核心').last);
    await tester.pumpAndSettle();
    expect(find.text('22.0%'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('核心 1').last);
    await tester.pumpAndSettle();
    expect(find.text('30.0%'), findsOneWidget);
    expect(find.text('22.0%'), findsNothing);
    expect(ssh.calls.length, count);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Chinese monitor entry opens and toggles the workspace panel', (
    tester,
  ) async {
    await tester.pumpWidget(app(width: 800, toolbar: true));
    await tester.tap(find.text('监控'));
    expect(layout.monitorPanelVisible, isTrue);
    layout.toggleSidePanel(SidePanel.terminalConfig);
    expect(layout.monitorPanelVisible, isFalse);
  });

  testWidgets(
    'connected host shows translated metrics and English switch without overflow',
    (tester) async {
      sessions.select(_session('a'));
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('50.0%'), findsWidgets);
      expect(find.text('内存'), findsOneWidget);
      expect(find.textContaining('0.25'), findsOneWidget);
      expect(find.text('Settings-a-very-long-host-name'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(locale: const Locale('en')));
      await tester.pump();
      expect(find.text('Memory'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'switching host discards delayed data, disconnect and watch stop polling',
    (tester) async {
      ssh.pending = Completer<_Result>();
      sessions.select(_session('a'));
      await tester.pumpWidget(app());
      final first = ssh.pending!;
      ssh.pending = null;
      sessions.select(_session('b'));
      await tester.pump();
      await tester.pump();
      expect(find.text('20.0%'), findsOneWidget);
      first.complete((stdout: _sample(90), stderr: '', exitCode: 0));
      await tester.pump();
      expect(find.text('90.0%'), findsNothing);
      (sessions.active as SshSession).status = SessionStatus.disconnected;
      sessions.notifyListeners();
      await tester.pump();
      final count = ssh.calls.length;
      await tester.pump(const Duration(seconds: 31));
      expect(ssh.calls.length, count);
      expect(find.text('20.0%'), findsNothing);
      sessions.select(SshSession.watch(watchedTitle: 'guest'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      expect(ssh.calls.length, count);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pause, resume and failures preserve last reading but never claim live',
    (tester) async {
      sessions.select(_session('a'));
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.byTooltip('暂停监控'));
      await tester.pump();
      final count = ssh.calls.length;
      await tester.pump(const Duration(seconds: 31));
      expect(ssh.calls.length, count);
      expect(find.text('已暂停'), findsOneWidget);
      ssh.fail = true;
      await tester.tap(find.byTooltip('继续监控'));
      await tester.pump();
      expect(find.textContaining('fixture unavailable'), findsOneWidget);
      expect(find.text('50.0%'), findsWidgets);
      expect(find.text('实时'), findsNothing);
      ssh.fail = false;
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      expect(find.textContaining('fixture unavailable'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

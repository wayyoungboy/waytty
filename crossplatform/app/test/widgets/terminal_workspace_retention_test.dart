import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/widgets/keep_alive_offstage.dart';
import 'package:yourssh/widgets/server_monitor_sheet.dart';
import 'package:yourssh/widgets/sftp_panel.dart';
import 'package:yourssh/widgets/split_terminal_view.dart';

class _Sessions extends ChangeNotifier implements SessionProvider {
  final session = SshSession(
    host: Host(label: 'fixture', host: 'fixture.invalid', username: 'fixture'),
    status: SessionStatus.connected,
  );
  @override
  AppSession get activeSession => session;
  @override
  List<AppSession> get sessions => [session];
  @override
  List<SshSession> get sshSessions => [session];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recording extends ChangeNotifier implements RecordingProvider {
  @override
  bool isRecording(String sessionId) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sftp extends Fake implements SftpClient {
  @override
  Future<List<SftpName>> listdir(String path) async => [];
  @override
  void close() {}
}

class _Ssh extends Fake implements SshService {
  int listings = 0;
  int probes = 0;
  @override
  Future<SftpClient> openSftp(Host host, {bool interactive = true}) async {
    listings++;
    return _Sftp();
  }

  @override
  Future<({String stdout, String stderr, int exitCode})> execForMonitoring(
    Host host,
    String command,
  ) async {
    probes++;
    return (
      stdout: command.contains('ufw')
          ? '__NO_FIREWALL__'
          : '''
__CPU1__
cpu 100 0 0 900 0 0 0 0 0 0
__CPU2__
cpu 150 0 0 950 0 0 0 0 0 0
__MEM__
MemTotal: 8192000 kB
MemAvailable: 4096000 kB
__UPTIME__
3600.0 0.0
''',
      stderr: '',
      exitCode: 0,
    );
  }
}

void main() {
  testWidgets('three-column workspace survives navigation and panel toggles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final sessions = _Sessions();
    final ssh = _Ssh();
    final layout = TerminalLayoutProvider()..toggleSidePanel(SidePanel.monitor);
    final settings = SettingsProvider();
    final shell = ShellIntegrationProvider();
    final recordings = _Recording();
    final plugins = PluginProvider(plugins: []);
    Widget app(bool visible) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(value: sessions),
        ChangeNotifierProvider.value(value: layout),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: shell),
        ChangeNotifierProvider.value(value: plugins),
        ChangeNotifierProvider<RecordingProvider>.value(value: recordings),
        Provider<SshService>.value(value: ssh),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: KeepAliveOffstage(
            active: visible,
            child: const SplitTerminalView(),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump();
    await tester.pump();
    final files = tester.state(find.byType(SftpPanel));
    final monitor = tester.state(find.byType(ServerMonitorSheet));
    expect(ssh.listings, 1);
    expect(ssh.probes, 2);
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(seconds: 31));
    expect(ssh.listings, 1);
    expect(ssh.probes, 2);
    await tester.pumpWidget(app(true));
    expect(tester.state(find.byType(SftpPanel)), same(files));
    expect(tester.state(find.byType(ServerMonitorSheet)), same(monitor));
    layout.toggleFiles();
    layout.toggleSidePanel(SidePanel.monitor);
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(ssh.probes, 2);
    layout.toggleFiles();
    layout.toggleSidePanel(SidePanel.monitor);
    await tester.pump();
    expect(tester.state(find.byType(SftpPanel)), same(files));
    expect(tester.state(find.byType(ServerMonitorSheet)), same(monitor));
    expect(ssh.listings, 1);
    expect(ssh.probes, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    for (final provider in [
      sessions,
      layout,
      settings,
      shell,
      recordings,
      plugins,
    ]) {
      provider.dispose();
    }
  });
}

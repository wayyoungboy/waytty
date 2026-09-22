import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/widgets/terminal_file_workspace.dart';
import 'package:yourssh/widgets/file_tree_view.dart';
import 'package:yourssh/widgets/sftp_panel.dart';
import 'package:yourssh/widgets/keep_alive_offstage.dart';

class _Sessions extends ChangeNotifier implements SessionProvider {
  AppSession? active;
  final all = <AppSession>[];
  @override
  AppSession? get activeSession => active;
  @override
  List<AppSession> get sessions => all;
  void select(AppSession value) {
    if (!all.contains(value)) all.add(value);
    active = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ssh extends Fake implements SshService {}

class _Transfer extends Fake implements SftpTransferService {
  final calls = <String>[];
  Completer<List<SftpEntry>>? pending;
  @override
  Future<List<SftpEntry>> listDirectory(Host host, String path) async {
    calls.add('${host.id}:$path');
    if (pending != null) return pending!.future;
    return [
      SftpEntry(
        name: path == '/' ? 'project-${host.id}' : 'main.dart',
        path: path == '/' ? '/project-${host.id}' : '$path/main.dart',
        isDirectory: path == '/',
        size: 0,
        modifiedAt: DateTime(2026),
      ),
    ];
  }
}

SshSession session(String id) => SshSession(
  host: Host(
    id: id,
    label: id,
    host: '$id.invalid',
    port: 22,
    username: 'fixture',
  ),
  status: SessionStatus.connected,
);

void main() {
  late _Sessions sessions;
  late _Transfer transfer;
  late TerminalLayoutProvider layout;
  late ShellIntegrationProvider shell;
  setUp(() {
    sessions = _Sessions();
    transfer = _Transfer();
    layout = TerminalLayoutProvider();
    shell = ShellIntegrationProvider();
  });
  Widget app({bool visible = true}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionProvider>.value(value: sessions),
      ChangeNotifierProvider.value(value: layout),
      ChangeNotifierProvider.value(value: shell),
      Provider<SshService>.value(value: _Ssh()),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: WayttyStrings.supportedLocales,
      localizationsDelegates: WayttyStrings.delegates,
      home: Scaffold(
        body: SizedBox(
          width: 240,
          child: KeepAliveOffstage(
            active: visible,
            child: Consumer<TerminalLayoutProvider>(
              builder: (_, p, _) => TerminalFileWorkspace(
                visible: p.filesVisible,
                transferService: transfer,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('switching away during a directory load retains the request and panel', (tester) async {
    final a = session('a');
    final b = session('b');
    sessions.select(a);
    final pending = Completer<List<SftpEntry>>();
    transfer.pending = pending;
    await tester.pumpWidget(app());
    await tester.pump();
    final state = tester.state(find.byType(SftpPanel));
    transfer.pending = null;
    sessions.select(b);
    await tester.pumpAndSettle();
    pending.complete([SftpEntry(name: 'ready.txt', path: '/ready.txt',
        isDirectory: false, size: 1, modifiedAt: DateTime(2026))]);
    await tester.pumpAndSettle();
    sessions.select(a);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(SftpPanel)), same(state));
    expect(find.text('ready.txt'), findsOneWidget);
    expect(transfer.calls, ['a:/', 'b:/']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('navigation and panel hiding preserve an in-flight folder expansion', (tester) async {
    sessions.select(session('a'));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final panel = tester.state(find.byType(SftpPanel));
    final pending = Completer<List<SftpEntry>>();
    transfer.pending = pending;
    await tester.tap(find.byTooltip('展开文件夹'));
    await tester.pump();
    layout.toggleFiles();
    await tester.pump();
    await tester.pumpWidget(app(visible: false));
    pending.complete([SftpEntry(name: 'loaded.txt', path: '/project-a/loaded.txt',
        isDirectory: false, size: 1, modifiedAt: DateTime(2026))]);
    await tester.pump();
    transfer.pending = null;
    layout.toggleFiles();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(SftpPanel)), same(panel));
    expect(find.text('loaded.txt'), findsOneWidget);
    expect(transfer.calls, ['a:/', 'a:/project-a']);
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(transfer.calls, ['a:/', 'a:/project-a', 'a:/']);
    expect(find.text('loaded.txt'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing an inactive session discards its late directory result', (tester) async {
    final a = session('a');
    sessions.select(a);
    final pending = Completer<List<SftpEntry>>();
    transfer.pending = pending;
    await tester.pumpWidget(app());
    await tester.pump();
    final panel = tester.state(find.byType(SftpPanel));
    transfer.pending = null;
    sessions.select(session('b'));
    await tester.pumpAndSettle();
    sessions.all.remove(a);
    sessions.notifyListeners();
    await tester.pump();
    expect(panel.mounted, false);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('project-b'), findsOneWidget);
    expect(transfer.calls, ['a:/', 'b:/']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('session trees survive switching, closing and reopening', (
    tester,
  ) async {
    final a = session('a');
    final b = session('b');
    sessions.select(a);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('文件工作区'), findsOneWidget);
    await tester.tap(find.byTooltip('展开文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);
    sessions.select(b);
    await tester.pumpAndSettle();
    expect(find.text('project-b'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);
    sessions.select(a);
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭文件工作区'));
    await tester.pumpAndSettle();
    expect(find.byType(FileTreeView<SftpEntry>), findsNothing);
    layout.toggleFiles();
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);
    expect(transfer.calls, ['a:/', 'a:/project-a', 'b:/']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late root loads, disconnected and watch sessions are isolated', (
    tester,
  ) async {
    final pending = Completer<List<SftpEntry>>();
    transfer.pending = pending;
    final a = session('a');
    sessions.select(a);
    await tester.pumpWidget(app());
    await tester.pump();
    transfer.pending = null;
    sessions.select(session('b'));
    await tester.pumpAndSettle();
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('project-b'), findsOneWidget);
    a.status = SessionStatus.disconnected;
    sessions.select(a);
    await tester.pumpAndSettle();
    final calls = transfer.calls.length;
    expect(find.text('选择已连接的 SSH 或本地终端以浏览文件'), findsOneWidget);
    sessions.select(SshSession.watch(watchedTitle: 'guest'));
    await tester.pumpAndSettle();
    expect(transfer.calls.length, calls);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('terminal directory is explicit and survives a new session on the same host', (tester) async {
    final a = session('shared');
    sessions.select(a);
    shell.handleOsc(a.id, '7', ['file://fixture/srv/project'], 0);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(transfer.calls, ['shared:/srv/project']);
    shell.handleOsc(a.id, '7', ['file://fixture/var/log'], 0);
    await tester.pumpAndSettle();
    expect(transfer.calls.length, 1, reason: 'shell cd must not disrupt manual browsing');
    await tester.tap(find.byTooltip('定位到终端当前目录'));
    await tester.pumpAndSettle();
    expect(transfer.calls.last, 'shared:/var/log');
    final b = session('shared');
    sessions.select(b);
    await tester.pumpAndSettle();
    expect(transfer.calls.last, 'shared:/');
    sessions.select(a);
    await tester.pumpAndSettle();
    expect(transfer.calls.length, 3, reason: 'returning to a session restores its own path');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

}

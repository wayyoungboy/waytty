import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import '../models/app_session.dart';
import '../models/local_entry.dart';
import '../models/local_session.dart';
import '../models/sftp_entry.dart';
import '../models/ssh_session.dart';
import '../providers/local_file_panel_provider.dart';
import '../providers/session_provider.dart';
import '../providers/sftp_panel_provider.dart';
import '../providers/shell_integration_provider.dart';
import '../providers/terminal_layout_provider.dart';
import '../services/app_discovery_service.dart';
import '../services/external_edit_service.dart';
import '../services/sftp_file_ops_service.dart';
import '../services/sftp_transfer_service.dart';
import '../services/ssh_service.dart';
import 'file_tree_view.dart';
import 'local_file_panel.dart';
import 'sftp_panel.dart';
import 'keep_alive_offstage.dart';

class _Files {
  final remote = SftpPanelProvider();
  final remoteTree = FileTreeCache<SftpEntry>();
  final localTree = FileTreeCache<LocalEntry>();
  LocalFilePanelProvider? local;
  void dispose() {
    remote.dispose();
    local?.dispose();
  }
}

/// Follows the active terminal and keeps each session's browsed path separate.
class TerminalFileWorkspace extends StatefulWidget {
  final bool visible;
  final SftpTransferService? transferService;
  const TerminalFileWorkspace({
    super.key,
    this.visible = true,
    this.transferService,
  });
  @override
  State<TerminalFileWorkspace> createState() => _TerminalFileWorkspaceState();
}

class _TerminalFileWorkspaceState extends State<TerminalFileWorkspace> {
  final _files = <String, _Files>{};
  late final SftpTransferService _transfer;
  late final SftpFileOpsService _operations;
  late final ExternalEditService _external;
  final _apps = AppDiscoveryService();
  @override
  void initState() {
    super.initState();
    final ssh = context.read<SshService>();
    _transfer = widget.transferService ?? SftpTransferService(ssh);
    _operations = SftpFileOpsService(ssh);
    _external = ExternalEditService(_transfer);
  }

  @override
  void dispose() {
    _external.dispose();
    _apps.dispose();
    for (final files in _files.values) {
      files.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>();
    final active = sessions.activeSession;
    final live = {
      for (final session in sessions.sessions)
        if (session is LocalSession ||
            (session is SshSession &&
                !session.isWatch &&
                session.status == SessionStatus.connected))
          session.id: session,
    };
    for (final id
        in _files.keys.where((id) => !live.containsKey(id)).toList()) {
      final removed = _files.remove(id)!;
      WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    }
    final visible = widget.visible && TickerMode.valuesOf(context).enabled;
    if (visible && live.containsKey(active?.id)) {
      _files.putIfAbsent(active!.id, _Files.new);
    }
    final shell = context.watch<ShellIntegrationProvider>();
    final content = Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in _files.entries)
          KeepAliveOffstage(
            key: ValueKey('workspace:${entry.key}'),
            active: visible && active?.id == entry.key,
            child: _buildPanel(
              live[entry.key]!,
              entry.value,
              shell.cwdFor(entry.key),
            ),
          ),
        if (!live.containsKey(active?.id))
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LText(
                'Select a connected SSH or local terminal to browse files',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
            ),
          ),
      ],
    );
    return MultiProvider(
      providers: [
        Provider<SftpTransferService>.value(value: _transfer),
        Provider<SftpFileOpsService>.value(value: _operations),
        Provider<ExternalEditService>.value(value: _external),
        Provider<AppDiscoveryService>.value(value: _apps),
      ],
      child: KeepAliveOffstage(
        active: widget.visible,
        child: Container(
          color: const Color(0xFF141414),
          child: Column(
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.account_tree_outlined,
                      size: 15,
                      color: Color(0xFF22C55E),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: LText(
                        'File workspace',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr(context, 'Close file workspace'),
                      onPressed: context
                          .read<TerminalLayoutProvider>()
                          .toggleFiles,
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(AppSession session, _Files files, String? cwd) {
    if (session is SshSession) {
      final workingDir = session.host.workingDir;
      final initialPath = cwd?.startsWith('/') == true
          ? cwd!
          : workingDir?.startsWith('/') == true
          ? workingDir!
          : '/';
      return SftpPanel(
        host: session.host,
        panelId: 'workspace:${session.id}',
        provider: files.remote,
        treeCache: files.remoteTree,
        terminalPath: cwd?.startsWith('/') == true ? cwd : null,
        initialPath: files.remoteTree.root ?? initialPath,
        onChangeHost: () {},
      );
    }
    files.local ??= cwd == null
        ? LocalFilePanelProvider()
        : LocalFilePanelProvider.atPath(cwd);
    return LocalFilePanel(provider: files.local!, treeCache: files.localTree);
  }
}

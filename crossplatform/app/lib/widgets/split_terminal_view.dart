import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import '../models/audit_event.dart';
import '../models/local_session.dart';
import '../models/pane_tree.dart';
import '../models/telnet_session.dart';
import 'telnet_terminal_pane.dart';
import '../models/ssh_session.dart';
import '../models/terminal_session.dart';
import '../providers/plugin_provider.dart';
import '../providers/terminal_layout_provider.dart';
import '../providers/session_provider.dart';
import '../providers/shell_integration_provider.dart';
import '../services/audit_service.dart';
import '../services/ssh_service.dart';
import '../providers/share_provider.dart';
import 'local_terminal_pane.dart';
import 'terminal_view.dart';
import 'terminal_input_bar.dart';
import 'broadcast_toolbar.dart';
import 'terminal_config_panel.dart';
import 'terminal_snippets_panel.dart';
import 'terminal_monitor_panel.dart';
import 'terminal_file_workspace.dart';
import 'workspace_side_panel.dart';
import 'keep_alive_offstage.dart';

class SplitTerminalView extends StatefulWidget {
  static const _dividerColor = Color(0xFF808080);
  static const _dividerThickness = 4.0;
  static const _focusBorder = Color(0xFF22C55E);

  final VoidCallback? onNavigateToSettings;
  const SplitTerminalView({super.key, this.onNavigateToSettings});

  @override
  State<SplitTerminalView> createState() => _SplitTerminalViewState();
}

class _SplitTerminalViewState extends State<SplitTerminalView> {

  void _sendCommand(TerminalSession session, String command) {
    session.terminal.textInput(command);
  }

  void _broadcastCommand(
    BuildContext context,
    List<TerminalSession> sessions,
    String command,
    TerminalLayoutProvider layout, {
    required String sourceSessionId,
  }) {
    if (!layout.broadcastEnabled) return;
    for (final s in sessions) {
      s.terminal.textInput(command);
    }
    try {
      final audit = context.read<AuditService>();
      final cmd = command.endsWith('\n')
          ? command.substring(0, command.length - 1)
          : command;
      for (final s in sessions) {
        if (s.id == sourceSessionId) continue;
        audit.record(
          AuditEvent.now(
            type: AuditEventType.input,
            host: s is SshSession ? s.host : null,
            sessionId: s.id,
            command: cmd,
            meta: const {'source': 'input-bar-broadcast'},
          ),
        );
      }
    } on ProviderNotFoundException {
      // Tests pumped without audit wiring.
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<TerminalLayoutProvider>();
    final snippetsEnabled = context.watch<PluginProvider>().isEnabled(
      YourSSHSnippetsPlugin.pluginId,
    );
    final sessionProvider = context.watch<SessionProvider>();
    final termSessions = sessionProvider.sessions
        .whereType<TerminalSession>()
        .toList();
    final activeRaw = sessionProvider.activeSession;
    final active = activeRaw is TerminalSession
        ? activeRaw
        : (termSessions.isNotEmpty ? termSessions[0] : null);

    if (termSessions.isEmpty || active == null) {
      return const Center(
        child: LText(
          "No active sessions",
          style: TextStyle(color: Color(0xFF555555)),
        ),
      );
    }

    // Bind the active terminal session into a pane group (singleton until split).
    // Defer provider writes out of build to avoid notifyListeners-during-build.
    final activeId = active.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lp = context.read<TerminalLayoutProvider>();
      lp.ensureGroup(activeId);
      lp.activateSession(activeId);
    });
    layout.ensureGroup(activeId, notify: false); // first-frame bind without notify
    final group = layout.groupForSession(activeId) ?? layout.activeGroup;
    if (group == null) {
      return const Center(
        child: LText(
          "No active sessions",
          style: TextStyle(color: Color(0xFF555555)),
        ),
      );
    }

    final groupSessions = <TerminalSession>[
      for (final id in group.sessionIds)
        ...termSessions.where((s) => s.id == id),
    ];

    return Column(
      children: [
        BroadcastToolbar(
          onSplitRight: () => _split(context, SplitAxis.horizontal),
          onSplitDown: () => _split(context, SplitAxis.vertical),
          onClosePane: () => _closePane(context),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasRightPanel =
                  layout.configPanelVisible ||
                  layout.monitorPanelVisible ||
                  (snippetsEnabled && layout.snippetsPanelVisible);
              final rightWidth = hasRightPanel
                  ? WorkspaceSidePanel.panelWidth
                  : 0.0;
              final available = constraints.maxWidth - rightWidth - 280;
              final filesWidth = layout.filesWidth.clamp(
                240.0,
                available.clamp(240.0, 520.0),
              );
              final minWidth =
                  (layout.filesVisible ? filesWidth + 5 : 0) + rightWidth + 280;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: constraints.maxWidth < minWidth
                      ? minWidth
                      : constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Row(
                    children: [
                      Offstage(
                        key: const ValueKey('terminal-files'),
                        offstage: !layout.filesVisible,
                        child: SizedBox(
                          width: filesWidth,
                          child: TerminalFileWorkspace(
                            visible: layout.filesVisible,
                          ),
                        ),
                      ),
                      if (layout.filesVisible)
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            key: const ValueKey('file-workspace-divider'),
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (event) =>
                                layout.resizeFiles(filesWidth + event.delta.dx),
                            child: const SizedBox(
                              width: 5,
                              child: Center(
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: Color(0xFF303030),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: _buildNode(
                          context,
                          group.root,
                          group,
                          groupSessions,
                          layout,
                        ),
                      ),
                      if (snippetsEnabled && layout.snippetsPanelVisible)
                        TerminalSnippetsPanel(
                          canRun: _canRunSnippetTarget(context),
                          onRunSnippet: (snippet) =>
                              _runSnippetOnActive(context, snippet.command),
                          onClose: layout.toggleSnippetsPanel,
                        ),
                      if (layout.configPanelVisible)
                        TerminalConfigPanel(
                          onClose: () =>
                              layout.toggleSidePanel(SidePanel.terminalConfig),
                          onOpenSettings: widget.onNavigateToSettings,
                        ),
                      KeepAliveOffstage(
                        key: const ValueKey('terminal-monitor'),
                        active: layout.monitorPanelVisible,
                        child: const TerminalMonitorPanel(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _split(BuildContext context, SplitAxis axis) async {
    final layout = context.read<TerminalLayoutProvider>();
    final sessions = context.read<SessionProvider>();
    final active = sessions.activeSession;
    if (active is! TerminalSession) return;
    layout.ensureGroup(active.id);
    layout.activateSession(active.id);
    final focused = layout.activeGroup?.focusedLeaf;
    if (focused == null) return;
    final newId = await sessions.openSiblingSession(focused.sessionId);
    if (!context.mounted || newId == null) return;
    layout.splitFocused(axis: axis, newSessionId: newId);
    sessions.setActive(newId);
    layout.activateSession(newId);
  }

  void _closePane(BuildContext context) {
    final layout = context.read<TerminalLayoutProvider>();
    final sessions = context.read<SessionProvider>();
    final closed = layout.closeFocusedPane();
    if (closed == null) {
      // Last pane — close the whole tab/group.
      final group = layout.activeGroup;
      if (group == null) {
        sessions.closeActive();
        return;
      }
      final ids = layout.removeGroup(group.id);
      sessions.closeSessions(ids.isEmpty ? [group.id] : ids);
      return;
    }
    sessions.closeSession(closed);
    final focus = layout.activeGroup?.focusedLeaf;
    if (focus != null) {
      sessions.setActive(focus.sessionId);
    }
  }

  bool _canRunSnippetTarget(BuildContext context) {
    final active = context.read<SessionProvider>().activeSession;
    return switch (active) {
      SshSession s => !s.isWatch && s.status == SessionStatus.connected,
      LocalSession s => s.status == LocalSessionStatus.running,
      TelnetSession s => s.status == TelnetStatus.connected,
      _ => false,
    };
  }

  void _runSnippetOnActive(BuildContext context, String command) {
    if (!_canRunSnippetTarget(context)) return;
    (context.read<SessionProvider>().activeSession! as TerminalSession).terminal
        .textInput('$command\n');
  }

  Widget _buildNode(
    BuildContext context,
    PaneNode node,
    TerminalGroup group,
    List<TerminalSession> groupSessions,
    TerminalLayoutProvider layout,
  ) {
    return switch (node) {
      PaneLeaf leaf => _buildPane(
          context,
          leaf,
          group,
          groupSessions,
          layout,
        ),
      PaneBranch branch => _buildBranch(
          context,
          branch,
          group,
          groupSessions,
          layout,
        ),
    };
  }

  Widget _buildBranch(
    BuildContext context,
    PaneBranch branch,
    TerminalGroup group,
    List<TerminalSession> groupSessions,
    TerminalLayoutProvider layout,
  ) {
    return _BranchLayout(
      axis: branch.axis,
      ratio: branch.ratio,
      thickness: SplitTerminalView._dividerThickness,
      color: SplitTerminalView._dividerColor,
      onResize: (newRatio) => layout.resizeBranch(branch.id, newRatio),
      first: _buildNode(
        context,
        branch.first,
        group,
        groupSessions,
        layout,
      ),
      second: _buildNode(
        context,
        branch.second,
        group,
        groupSessions,
        layout,
      ),
    );
  }

  Widget _buildPane(
    BuildContext context,
    PaneLeaf leaf,
    TerminalGroup group,
    List<TerminalSession> groupSessions,
    TerminalLayoutProvider layout,
  ) {
    final session = groupSessions.where((s) => s.id == leaf.sessionId).firstOrNull;
    if (session == null) return _buildEmptyPane();

    final focused = group.focusedPaneId == leaf.id;
    final showInput = layout.inputBarVisible &&
        (focused || layout.broadcastEnabled);

    return Container(
      key: ValueKey('pane-${leaf.id}'),
      decoration: BoxDecoration(
        border: Border.all(
          color: focused ? SplitTerminalView._focusBorder : const Color(0xFF2A2A2A),
          width: focused ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          if (session is SshSession && session.isWatch)
            _WatchBanner(session: session),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                layout.focusPane(leaf.id);
                context.read<SessionProvider>().setActive(session.id);
              },
              child: _paneContent(context, session),
            ),
          ),
          if (showInput)
            TerminalInputBar(
              sessionId: session.id,
              cwd: context.select<ShellIntegrationProvider, String?>(
                (p) => p.cwdFor(session.id),
              ),
              listDir: session is SshSession
                  ? (dir) => context.read<SshService>().listDirectory(
                      session.host,
                      dir,
                    )
                  : null,
              onSubmit: (cmd) {
                if (layout.broadcastEnabled) {
                  _broadcastCommand(
                    context,
                    groupSessions,
                    cmd,
                    layout,
                    sourceSessionId: session.id,
                  );
                } else {
                  _sendCommand(session, cmd);
                }
              },
              onDismiss: () => layout.toggleInputBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyPane() {
    return const Center(
      child: LText(
        "No session",
        style: TextStyle(color: Color(0xFF555555), fontSize: 13),
      ),
    );
  }

  Widget _paneContent(BuildContext context, TerminalSession session) {
    return switch (session) {
      TelnetSession() => TelnetTerminalPane(
        key: ValueKey(session.id),
        session: session,
      ),
      LocalSession() => LocalTerminalPane(
        key: ValueKey(session.id),
        session: session,
        onRestart: () =>
            context.read<SessionProvider>().restartLocalSession(session.id),
      ),
      SshSession() => SessionTerminalView(
        key: ValueKey(session.id),
        session: session,
      ),
      _ => throw UnsupportedError(
        'Unknown TerminalSession type: ${session.runtimeType}',
      ),
    };
  }
}

/// Renders a split with a draggable divider; reports ratio changes.
class _BranchLayout extends StatelessWidget {
  final SplitAxis axis;
  final double ratio;
  final double thickness;
  final Color color;
  final ValueChanged<double> onResize;
  final Widget first;
  final Widget second;

  const _BranchLayout({
    required this.axis,
    required this.ratio,
    required this.thickness,
    required this.color,
    required this.onResize,
    required this.first,
    required this.second,
  });

  @override
  Widget build(BuildContext context) {
    final isRow = axis == SplitAxis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent =
            (isRow ? constraints.maxWidth : constraints.maxHeight) - thickness;
        final firstExtent = (maxExtent * ratio).clamp(maxExtent * 0.1, maxExtent * 0.9);
        final secondExtent = maxExtent - firstExtent;

        Widget divider = MouseRegion(
          cursor: isRow
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: isRow
                ? (d) {
                    final next = (firstExtent + d.delta.dx) / maxExtent;
                    onResize(next);
                  }
                : null,
            onVerticalDragUpdate: !isRow
                ? (d) {
                    final next = (firstExtent + d.delta.dy) / maxExtent;
                    onResize(next);
                  }
                : null,
            child: ColoredBox(
              color: color.withValues(alpha: 0.35),
              child: SizedBox(
                width: isRow ? thickness : double.infinity,
                height: isRow ? double.infinity : thickness,
              ),
            ),
          ),
        );

        if (isRow) {
          return Row(
            children: [
              SizedBox(width: firstExtent, child: first),
              divider,
              SizedBox(width: secondExtent, child: second),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(height: firstExtent, child: first),
            divider,
            SizedBox(height: secondExtent, child: second),
          ],
        );
      },
    );
  }
}

class _WatchBanner extends StatelessWidget {
  final SshSession session;
  const _WatchBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final share = context.watch<ShareProvider>();
    final hasControl = share.isGuest && share.hasControl;
    final sessionEnded = share.isGuest && share.sessionEnded;

    Color bg;
    Color fg;
    String label;

    if (sessionEnded) {
      bg = const Color(0xFF2A1A1A);
      fg = const Color(0xFFCC4444);
      label = 'Session ended by host';
    } else if (hasControl) {
      bg = const Color(0xFF1A2A1A);
      fg = const Color(0xFF22C55E);
      label = 'You have control';
    } else {
      bg = const Color(0xFF1A1A2A);
      fg = const Color(0xFF6699CC);
      label = 'Watching: ${session.watchedTitle ?? ''} · Read-only';
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.screen_share_outlined, size: 12, color: fg),
          const SizedBox(width: 6),
          LText(label, style: TextStyle(color: fg, fontSize: 11)),
          const Spacer(),
          if (!sessionEnded)
            GestureDetector(
              onTap: () => context.read<ShareProvider>().leaveSession(),
              child: LText(
                "Leave",
                style: TextStyle(
                  color: fg.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import '../models/ssh_session.dart';
import '../providers/session_provider.dart';
import '../providers/terminal_layout_provider.dart';
import 'server_monitor_sheet.dart';
import 'workspace_side_panel.dart';

class TerminalMonitorPanel extends StatelessWidget {
  const TerminalMonitorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final active = context.watch<SessionProvider>().activeSession;
    return WorkspaceSidePanel(
      title: 'Monitor',
      closeTooltip: 'Close monitor',
      onClose: () => context.read<TerminalLayoutProvider>().toggleSidePanel(
        SidePanel.monitor,
      ),
      child: active is SshSession && !active.isWatch
          ? ServerMonitorSheet(
              key: ValueKey(active.id),
              host: active.host,
              embedded: true,
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LText(
                  'Select a connected SSH session to monitor',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFAAAAAA)),
                ),
              ),
            ),
    );
  }
}

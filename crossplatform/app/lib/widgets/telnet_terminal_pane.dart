import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../models/telnet_session.dart';
import '../providers/settings_provider.dart';
import '../theme/terminal_themes.dart';
import '../providers/session_provider.dart';
import 'record_button.dart';
import 'terminal_context_menu.dart';

class TelnetTerminalPane extends StatefulWidget {
  const TelnetTerminalPane({super.key, required this.session});
  final TelnetSession session;
  @override
  State<TelnetTerminalPane> createState() => _TelnetTerminalPaneState();
}

class _TelnetTerminalPaneState extends State<TelnetTerminalPane> {
  final _controller = TerminalController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Stack(
        children: [
          TerminalView(
            session.terminal,
            autofocus: true,
            controller: _controller,
            theme: terminalThemeByName(settings.terminalTheme),
            textStyle: TerminalStyle(
              fontFamily: settings.terminalFont,
              fontSize: settings.fontSize,
            ),
            onSecondaryTapUp: (details, _) => showTerminalContextMenu(
              context: context,
              globalPosition: details.globalPosition,
              terminal: session.terminal,
              controller: _controller,
            ),
          ),
          if (session.status == TelnetStatus.connecting)
            const Center(child: CircularProgressIndicator()),
          if (session.status == TelnetStatus.error ||
              session.status == TelnetStatus.closed)
            Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: const Color(0xFF252525),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(child: Text(session.error ?? tr(context, 'Connection closed'))),
                      TextButton(
                        onPressed: () {
                          final provider = context.read<SessionProvider>();
                          provider.closeSession(session.id);
                          provider.connectAny(session.host);
                        },
                        child: const LText("重新连接"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(top: 8, right: 8, child: RecordButton(session: session)),
        ],
      ),
    );
  }
}

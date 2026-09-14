import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import '../../models/serial_session.dart';
import '../../providers/session_provider.dart';
import '../../widgets/serial/serial_connection_panel.dart';
import '../../widgets/serial/serial_session_pane.dart';

class MobileSerialScreen extends StatelessWidget {
  const MobileSerialScreen({super.key});
  void _show(BuildContext context, SerialSession session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const LText('Serial debugger')),
          body: SafeArea(child: SerialSessionPane(session: session)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionProvider>();
    final sessions = provider.sessions.whereType<SerialSession>().toList();
    return Scaffold(
      appBar: AppBar(title: const LText('Serial debugger')),
      body: SafeArea(
        child: Column(
          children: [
            if (sessions.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final session in sessions)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: InputChip(
                          avatar: const Icon(Icons.cable, size: 18),
                          label: Text(session.tabLabel),
                          onPressed: () => _show(context, session),
                          onDeleted: () => provider.closeSession(session.id),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: SerialConnectionPanel(
                onConnect: (device, config, backend) async {
                  // Open the route immediately, keeping Cancel reachable during USB permission.
                  final previous = provider.activeSession;
                  final opening = provider.connectSerial(
                    device,
                    config,
                    backend,
                  );
                  final session = provider.activeSession;
                  if (session is SerialSession && session != previous) {
                    _show(context, session);
                  }
                  await opening;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

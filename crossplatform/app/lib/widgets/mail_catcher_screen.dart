import 'package:waytty_l10n/waytty_l10n.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../services/mail_catcher_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

class MailCatcherScreen extends StatefulWidget {
  const MailCatcherScreen({super.key});

  @override
  State<MailCatcherScreen> createState() => _MailCatcherScreenState();
}

class _MailCatcherScreenState extends State<MailCatcherScreen> {
  late MailCatcherService _service;
  bool _running = false;
  List<CaughtEmail> _emails = [];
  CaughtEmail? _selected;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _service = MailCatcherService(context.read<SshService>());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final session = context.read<SessionProvider>().activeSshSession;
    if (session == null) return;
    final ok = await _service.start(session.host);
    if (ok) {
      setState(() => _running = true);
      _pollTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LText(
              "Failed to start SMTP server. Ensure python3 is installed."),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<void> _stop() async {
    final session = context.read<SessionProvider>().activeSshSession;
    if (session == null) return;
    _pollTimer?.cancel();
    await _service.stop(session.host);
    setState(() => _running = false);
  }

  Future<void> _poll() async {
    final session = context.read<SessionProvider>().activeSshSession;
    if (session == null) return;
    final emails = await _service.fetchEmails(session.host);
    if (mounted) setState(() => _emails = emails);
  }

  String _fmtTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return tr(context, 'just now');
    if (diff.inMinutes < 60) return tr(context, LMessage('{0}m ago', [diff.inMinutes]));
    if (diff.inHours < 24) return tr(context, LMessage('{0}h ago', [diff.inHours]));
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: AppColors.sidebar,
                child: Row(
                  children: [
                    const LText("Mail Catcher",
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    if (_emails.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: LText(
                          LMessage("{0}", [_emails.length]),
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (_emails.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined,
                            size: 16, color: AppColors.textTertiary),
                        onPressed: () => setState(() {
                          _emails = [];
                          _selected = null;
                        }),
                        tooltip: tr(context, "Clear all"),
                      ),
                    _running
                        ? IconButton(
                            icon: const Icon(Icons.stop,
                                size: 16, color: AppColors.red),
                            onPressed: _stop,
                            tooltip: tr(context, "Stop"),
                          )
                        : IconButton(
                            icon: const Icon(Icons.play_arrow,
                                size: 16, color: AppColors.accent),
                            onPressed: context
                                        .watch<SessionProvider>()
                                        .activeSshSession !=
                                    null
                                ? _start
                                : null,
                            tooltip: tr(context, "Start on port 1025"),
                          ),
                  ],
                ),
              ),
              if (_running)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  color: AppColors.accent.withValues(alpha: 0.1),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: AppColors.accent),
                      SizedBox(width: 6),
                      LText("Listening on :1025",
                          style: TextStyle(
                              color: AppColors.accent, fontSize: 11)),
                    ],
                  ),
                ),
              Expanded(
                child: Material(
                  color: AppColors.sidebar,
                  child: _emails.isEmpty
                    ? const Center(
                        child: LText("No emails captured",
                            style: TextStyle(color: AppColors.textTertiary)),
                      )
                    : ListView.builder(
                        itemCount: _emails.length,
                        itemBuilder: (_, i) => ListTile(
                          selected: _selected == _emails[i],
                          title: LText(
                            _emails[i].subject.isEmpty ? "(no subject)" : LRaw(_emails[i].subject),
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                          ),
                          subtitle: LText(
                            LMessage("{0} · {1}", [_emails[i].from, _fmtTime(_emails[i].receivedAt)]),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                          onTap: () =>
                              setState(() => _selected = _emails[i]),
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.border),
        Expanded(
          child: _selected == null
              ? const Center(
                  child: LText("Select an email",
                      style: TextStyle(color: AppColors.textTertiary)),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LText(LMessage("Subject: {0}", [_selected!.subject]),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      LText(LMessage("From: {0}", [_selected!.from]),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      LText(LMessage("To: {0}", [_selected!.to]),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      LText(
                        LMessage("Received: {0}", [_fmtTime(_selected!.receivedAt)]),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const Divider(color: AppColors.border, height: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _selected!.body,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

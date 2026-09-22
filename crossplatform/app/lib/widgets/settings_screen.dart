import 'package:waytty_l10n/waytty_l10n.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path_util;
import 'package:uuid/uuid.dart';
import '../models/ai_provider_config.dart';
import '../models/shell_profile.dart';
import '../providers/ai_chat_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/audit_provider.dart';
import '../services/sync_service.dart';
import '../providers/host_provider.dart';
import '../theme/app_theme.dart';
import 'hotkey_settings_screen.dart';
import 'terminal_appearance_controls.dart';
import 'keyword_highlight_settings.dart';
import 'confirm_dialog.dart';
import 'account_vault_section.dart';
import 'qr_export_dialog.dart';
import 'qr_import_dialog.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/update_provider.dart';
import '../models/app_release.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final update = context.watch<UpdateProvider>();

    return Material(
      color: AppColors.bg,
      child: Column(
        children: [
          Container(
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.sidebar,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: const LText("Settings", style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const LanguagePicker(),
                const SizedBox(height: 24),
                _Section(title: tr(context, "Connection"), children: [
                  _Row(
                    label: tr(context, "Auto-reconnect"),
                    subtitle: tr(context, "Reconnect when connection drops"),
                    trailing: Switch(
                      value: settings.autoReconnect,
                      activeThumbColor: AppColors.accent,
                      onChanged: (v) => context.read<SettingsProvider>().save(autoReconnect: v),
                    ),
                  ),
                  _Row(
                    label: tr(context, "Max reconnect attempts"),
                    trailing: _DropDown<int>(
                      value: settings.reconnectAttempts,
                      items: [0, 1, 3, 5, 10],
                      labelOf: (n) => tr(context, n == 0 ? 'Unlimited' : LMessage('{0} times', [n])),
                      onChanged: (v) => context.read<SettingsProvider>().save(reconnectAttempts: v),
                    ),
                  ),
                  _Row(
                    label: tr(context, "Keep-alive interval"),
                    subtitle: tr(context, "How often to ping the server to keep the connection alive"),
                    trailing: _DropDown<int>(
                      value: settings.keepAliveInterval,
                      items: [10, 30, 60, 0],
                      labelOf: (n) => n == 0 ? tr(context, 'Off') : '${n}s',
                      onChanged: (v) => context.read<SettingsProvider>().save(keepAliveInterval: v),
                    ),
                  ),
                  SwitchListTile(
                    title: const LText("Tmux Integration", style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const LText("Attach to tmux session on connect (requires tmux on server)", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.tmuxEnabled,
                    onChanged: (v) {
                      settings.tmuxEnabled = v;
                      settings.save();
                    },
                  ),
                  SwitchListTile(
                    title: const LText("Shell Integration", style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const LText("Detect cwd, command status & exit codes on bash/zsh (cwd in tab, gutter markers, jump-to-prompt, path completion)", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.shellIntegrationEnabled,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .save(shellIntegrationEnabled: v),
                  ),
                ]),
                const SizedBox(height: 24),
                _Section(title: tr(context, "Terminal"), children: [
                  _Row(
                    label: tr(context, "Terminal emulation type"),
                    subtitle: tr(context, "TERM reported to the server — applies to new SSH connections"),
                    trailing: _DropDown<String>(
                      value: settings.terminalType,
                      items: kTermTypes,
                      labelOf: (t) => t,
                      onChanged: (v) => context.read<SettingsProvider>().save(terminalType: v),
                    ),
                  ),
                  Consumer<SettingsProvider>(
                    builder: (context, settings, _) {
                      const platformDefault = kPlatformDefaultShellId;
                      final profiles = settings.allShellProfiles;
                      final ids = {for (final s in profiles) s.id};
                      final value = settings.defaultShellId != null &&
                              ids.contains(settings.defaultShellId)
                          ? settings.defaultShellId!
                          : platformDefault;
                      return _Row(
                        label: tr(context, "Default local shell"),
                        subtitle: tr(context, "Shell used by new local terminals"),
                        trailing: _DropDown<String>(
                          value: value,
                          items: [
                            platformDefault,
                            for (final s in profiles) s.id,
                          ],
                          labelOf: (id) => id == platformDefault
                              ? tr(context, 'Platform default')
                              : profiles.firstWhere((s) => s.id == id).name,
                          onChanged: (id) => context
                              .read<SettingsProvider>()
                              .setDefaultShellId(
                                  id == platformDefault ? null : id),
                        ),
                      );
                    },
                  ),
                  const _CustomShellsRows(),
                  const TerminalAppearanceControls(layout: AppearanceControlsLayout.rows),
                ]),
                const SizedBox(height: 24),
                _Section(title: tr(context, "Keyword Highlighting"), children: [
                  const KeywordHighlightSection(),
                ]),
                const SizedBox(height: 24),
                _Section(title: tr(context, "Recording"), children: [
                  Consumer<SettingsProvider>(
                    builder: (context, settings, _) => _Row(
                      label: tr(context, "Recording path"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              settings.recordingPath,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              final result = await FilePicker.platform.getDirectoryPath(
                                dialogTitle: tr(context, 'Choose recordings folder'),
                              );
                              if (result != null && context.mounted) {
                                await context.read<SettingsProvider>().save(recordingPath: result);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: const BorderSide(color: AppColors.border),
                              foregroundColor: AppColors.textSecondary,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            child: const LText("Change…"),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const LText("Redact secrets in recordings", style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const LText("Mask passwords/tokens (AuditRedactor patterns) before writing .cast — replay timing becomes per-line; per-host opt-out in the host panel", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.recordingRedactionEnabled,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .save(recordingRedactionEnabled: v),
                  ),
                ]),
                const SizedBox(height: 24),
                _Section(title: tr(context, "Monitoring"), children: [
                  SwitchListTile(
                    title: const LText("Network Stats Monitor", style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const LText("Show Rx/Tx overlay on active session", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.networkStatsEnabled,
                    onChanged: (v) {
                      settings.networkStatsEnabled = v;
                      settings.save();
                    },
                  ),
                  SwitchListTile(
                    title: const LText("Command finish notification", style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const LText("Alert when a command completes in an unfocused session", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.commandNotificationsEnabled,
                    onChanged: (v) => context.read<SettingsProvider>().save(commandNotificationsEnabled: v),
                  ),
                ]),
                const SizedBox(height: 24),
                _Section(title: tr(context, "Audit"), children: [
                  _Row(
                    label: tr(context, "Retention"),
                    subtitle: tr(context, "Delete audit events older than this on launch"),
                    trailing: _DropDown<int>(
                      value: const [30, 90, 365, 0]
                              .contains(settings.auditRetentionDays)
                          ? settings.auditRetentionDays
                          : 90,
                      items: const [30, 90, 365, 0],
                      labelOf: (d) => tr(context, d == 0 ? 'Keep forever' : LMessage('{0} days', [d])),
                      onChanged: (d) =>
                          settings.save(auditRetentionDays: d),
                    ),
                  ),
                  _Row(
                    label: tr(context, "Clear audit log"),
                    subtitle: tr(context, "Delete all recorded events now"),
                    trailing: TextButton.icon(
                      icon: const Icon(Icons.delete_outline,
                          size: 14, color: Colors.red),
                      label: const LText("Clear",
                          style: TextStyle(fontSize: 12, color: Colors.red)),
                      onPressed: () => _confirmClearAudit(context),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                const _SecuritySection(),
                const SizedBox(height: 24),
                const AccountVaultSection(),
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const LText('P2P Transfer'),
                  children: [const _SyncSection()],
                ),
                const SizedBox(height: 24),
                const _AiProvidersSection(),
                const SizedBox(height: 24),
                _Section(title: tr(context, "Keyboard"), children: [
                  _Row(
                    label: tr(context, "Keyboard Shortcuts"),
                    trailing: TextButton.icon(
                      icon: const Icon(Icons.keyboard_outlined, size: 14),
                      label: const LText("Configure", style: TextStyle(fontSize: 12)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HotkeySettingsScreen()),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                if (update.enabled) _Section(title: tr(context, "Updates"), children: [
                  _Row(
                    label: tr(context, "Current version"),
                    trailing: LText(
                      LMessage("v{0}", [update.currentVersion]),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                  _Row(
                    label: tr(context, "Status"),
                    subtitle: _updateStatusText(update),
                    trailing: update.status == UpdateStatus.downloading
                        ? SizedBox(
                            width: 120,
                            child: LinearProgressIndicator(value: update.downloadProgress),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (update.status == UpdateStatus.available) ...[
                                FilledButton(
                                  onPressed: () =>
                                      context.read<UpdateProvider>().downloadAndInstall(),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                    foregroundColor: Colors.black,
                                    textStyle: const TextStyle(fontSize: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  child: const LText("Download & install"),
                                ),
                                const SizedBox(width: 8),
                              ],
                              OutlinedButton(
                                onPressed: update.status == UpdateStatus.checking
                                    ? null
                                    : () => context
                                        .read<UpdateProvider>()
                                        .checkForUpdates(manual: true),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.border),
                                  foregroundColor: AppColors.textSecondary,
                                  textStyle: const TextStyle(fontSize: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                child: const LText("Check for updates"),
                              ),
                            ],
                          ),
                  ),
                  if (update.status == UpdateStatus.available &&
                      update.latestRelease != null &&
                      update.latestRelease!.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        update.latestRelease!.notes,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _updateStatusText(UpdateProvider u) {
    switch (u.status) {
      case UpdateStatus.checking:
        return 'Checking…';
      case UpdateStatus.upToDate:
        return 'You are on the latest version';
      case UpdateStatus.available:
        return tr(context, LMessage('New version v{0} available', [u.latestRelease?.version ?? '?']));
      case UpdateStatus.downloading:
        return 'Downloading…';
      case UpdateStatus.readyToInstall:
        return 'Installer opened — complete it to finish updating';
      case UpdateStatus.error:
        return u.errorMessage ?? 'Could not check for updates';
      case UpdateStatus.idle:
        return 'Click "Check for updates" to look for a new version';
    }
  }

  Future<void> _confirmClearAudit(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Clear audit log?',
      message: 'All recorded events will be deleted.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      // Through the provider (not AuditService directly) so an open Audit
      // Log screen refreshes instead of showing stale deleted rows.
      context.read<AuditProvider>().clearAll();
    } on ProviderNotFoundException {
      // Settings pumped without audit wiring (tests).
    }
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection();

  Future<void> _showQrExport(BuildContext context) async {
    final hostProvider = context.read<HostProvider>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QrExportDialog(
        getPayload: () async {
          final hosts = hostProvider.allHosts;
          final passwords = await hostProvider.loadAllPasswords();
          return SyncService.buildPayload(hosts: hosts, passwords: passwords);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _buildP2pTab(context);

  Widget _buildP2pTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LText(
            "Transfer all hosts and passwords to another device over LAN or Tailscale. No cloud required.",
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code, size: 16),
                  label: const LText("Show QR Code"),
                  onPressed: () => _showQrExport(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: const LText("Import via Code"),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const QrImportDialog(),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiProvidersSection extends StatefulWidget {
  const _AiProvidersSection();

  @override
  State<_AiProvidersSection> createState() => _AiProvidersSectionState();
}

class _AiProvidersSectionState extends State<_AiProvidersSection> {
  final _controllers = <AiProvider, TextEditingController>{};
  final _focusNodes = <AiProvider, FocusNode>{};
  final _showKey = <AiProvider, bool>{};

  @override
  void initState() {
    super.initState();
    for (final p in AiProvider.values) {
      _controllers[p] = TextEditingController();
      _showKey[p] = false;
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus && mounted) _saveKey(p);
      });
      _focusNodes[p] = node;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final configs = context.read<AiChatProvider>().configs;
    for (final p in AiProvider.values) {
      if (_controllers[p]!.text.isEmpty && configs[p] != null) {
        _controllers[p]!.text = configs[p]!.apiKey;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _saveKey(AiProvider p) {
    final key = _controllers[p]!.text.trim();
    if (key.isEmpty) return;
    context.read<AiChatProvider>().setProviderConfig(p, apiKey: key);
  }

  String _label(AiProvider p) => switch (p) {
        AiProvider.anthropic => 'Anthropic',
        AiProvider.openai => 'OpenAI',
        AiProvider.gemini => 'Google Gemini',
      };

  String _hint(AiProvider p) => switch (p) {
        AiProvider.anthropic => 'sk-ant-...',
        AiProvider.openai => 'sk-...',
        AiProvider.gemini => 'AIza...',
      };

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiChatProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LText(
          "AI PROVIDERS",
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...AiProvider.values.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildCard(context, ai, p),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, AiChatProvider ai, AiProvider p) {
    final config = ai.configs[p];
    final models = {...AiChatProvider.presetModels[p]!, if (config != null) config.model}.toList();
    final selectedModel = config?.model ?? models.first;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _label(p),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (config != null)
                const Icon(Icons.check_circle, size: 14, color: Colors.green),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controllers[p],
            focusNode: _focusNodes[p],
            obscureText: !_showKey[p]!,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: _hint(p),
              hintStyle:
                  const TextStyle(color: AppColors.textTertiary, fontSize: 12),
              filled: true,
              fillColor: AppColors.bg,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _showKey[p]! ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    onPressed: () =>
                        setState(() => _showKey[p] = !_showKey[p]!),
                  ),
                  if (config != null)
                    IconButton(
                      icon: const Icon(Icons.clear,
                          size: 16, color: AppColors.textTertiary),
                      onPressed: () {
                        _controllers[p]!.clear();
                        context.read<AiChatProvider>().clearProviderConfig(p);
                      },
                    ),
                ],
              ),
            ),
            onSubmitted: (_) => _saveKey(p),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const LText(
                "Model",
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: selectedModel,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 12),
                dropdownColor: AppColors.card,
                underline: const SizedBox(),
                isDense: true,
                items: models
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m, style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    context.read<AiChatProvider>().setProviderConfig(p, model: v);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(initialValue: config?.model,
            decoration:  InputDecoration(labelText: tr(context, "自定义模型 ID（回车保存）")),
            onFieldSubmitted: (value) {
              if (value.trim().isNotEmpty) context.read<AiChatProvider>().setProviderConfig(p, model: value.trim());
            }),
          if (p != AiProvider.gemini) TextFormField(initialValue: config?.endpoint,
            decoration:  InputDecoration(labelText: tr(context, "自定义 API 完整地址（回车保存）"),
              hintText: tr(context, "https://example.com/v1/chat/completions")),
            onFieldSubmitted: (value) async {
              try { await context.read<AiChatProvider>().setProviderConfig(p, endpoint: value.trim()); }
              catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LText(LMessage("{0}", [e])))); }
            }),
        ],
      ),
    );
  }
}

// ── Custom local shells (Settings → Terminal) ─────────────

class _CustomShellsRows extends StatelessWidget {
  const _CustomShellsRows();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final shell in settings.customShellProfiles)
          _Row(
            label: shell.name,
            subtitle: [shell.executable, ...shell.args].join(' '),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.textSecondary),
              tooltip: tr(context, "Remove custom shell"),
              onPressed: () => context
                  .read<SettingsProvider>()
                  .removeCustomShellProfile(shell.id),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 2, bottom: 6),
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 14),
            label: const LText("Add custom shell…",
                style: TextStyle(fontSize: 12)),
            onPressed: () => _showAddCustomShellDialog(context),
          ),
        ),
      ],
    );
  }
}

Future<void> _showAddCustomShellDialog(BuildContext context) async {
  final settings = context.read<SettingsProvider>();
  final profile = await showDialog<ShellProfile>(
    context: context,
    builder: (_) => const _AddShellDialog(),
  );
  if (profile != null) await settings.addCustomShellProfile(profile);
}

/// Stateful so the TextEditingControllers are disposed by the route teardown
/// (State.dispose), not while the dialog's exit animation still references
/// the text fields.
class _AddShellDialog extends StatefulWidget {
  const _AddShellDialog();

  @override
  State<_AddShellDialog> createState() => _AddShellDialogState();
}

class _AddShellDialogState extends State<_AddShellDialog> {
  final _nameCtrl = TextEditingController();
  final _exeCtrl = TextEditingController();
  final _argsCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _exeCtrl.dispose();
    _argsCtrl.dispose();
    super.dispose();
  }

  /// Null when the executable is empty — Add then behaves like Cancel.
  ShellProfile? _buildProfile() {
    final exe = _exeCtrl.text.trim();
    if (exe.isEmpty) return null;
    final name = _nameCtrl.text.trim();
    final argsText = _argsCtrl.text.trim();
    return ShellProfile(
      id: 'custom-${const Uuid().v4()}',
      name: name.isEmpty ? path_util.basename(exe) : name,
      executable: exe,
      args: argsText.isEmpty ? const [] : argsText.split(RegExp(r'\s+')),
      isCustom: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const LText("Add custom shell", style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration:  InputDecoration(labelText: tr(context, "Display name")),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _exeCtrl,
                  decoration:
                       InputDecoration(labelText: tr(context, "Executable path")),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.folder_open, size: 16),
                tooltip: tr(context, "Browse…"),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles();
                  final path = result?.files.single.path;
                  if (path != null) _exeCtrl.text = path;
                },
              ),
            ]),
            TextField(
              controller: _argsCtrl,
              decoration:  InputDecoration(
                labelText: tr(context, "Arguments"),
                helperText: tr(context, "Space-separated; quoting not supported"),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText("Cancel")),
        TextButton(
            onPressed: () => Navigator.pop(context, _buildProfile()),
            child: const LText("Add")),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LText(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: children.indexed.map((e) {
                final (i, child) = e;
                return Column(children: [
                  child,
                  if (i < children.length - 1)
                    const Divider(height: 1, color: AppColors.border, indent: 16),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Credentials are supplied manually and retained only in process memory.
class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) => _Section(
    title: tr(context, 'Security'),
    children: [
      _Row(
        label: tr(context, 'Credential storage'),
        subtitle: tr(context, 'Enter credentials manually. Private keys and passwords are not loaded from the system keychain or saved to disk.'),
        trailing: const LText('Memory only'),
      ),
    ],
  );
}

class _Row extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget? trailing;
  const _Row({required this.label, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: LText(subtitle!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _DropDown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final void Function(T) onChanged;
  const _DropDown({required this.value, required this.items, required this.labelOf, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      dropdownColor: AppColors.card,
      underline: const SizedBox(),
      items: items.map((i) => DropdownMenuItem(value: i, child: LText(labelOf(i)))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}

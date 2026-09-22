import 'package:waytty_l10n/waytty_l10n.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../services/workspace_service.dart';
import '../models/host.dart';
import '../models/local_session.dart';
import '../models/serial_session.dart';
import '../widgets/serial/serial_session_pane.dart';
import '../models/ssh_session.dart';
import '../models/terminal_session.dart';
import '../providers/ai_chat_provider.dart';
import '../providers/host_provider.dart';
import '../providers/known_hosts_provider.dart';
import '../providers/session_provider.dart';
import '../providers/recording_provider.dart';
import '../main.dart' show kAppVersion;
import '../theme/app_theme.dart';
import '../widgets/host_detail_panel.dart';
import '../widgets/connection_center.dart';
import 'notes_screen.dart';
import 'mcp_screen.dart';
import '../widgets/keychain_screen.dart';
import '../widgets/known_hosts_screen.dart';
import '../widgets/ssh_host_key_dialog.dart';
import '../widgets/port_forwarding_screen.dart';
import '../widgets/settings_screen.dart';
import '../widgets/network_stats_overlay.dart';
import '../widgets/dual_panel_sftp_screen.dart';
import '../widgets/keep_alive_offstage.dart';
import '../widgets/split_terminal_view.dart';
import '../widgets/new_group_panel.dart';
import '../widgets/import_panel.dart';
import '../widgets/ai_chat_sidebar.dart';
import '../widgets/command_palette.dart';
import '../widgets/plugin_consent_dialog.dart';
import '../widgets/plugin_manager_screen.dart';
import '../widgets/audit_screen.dart';
import '../widgets/recording_library_screen.dart';
import '../plugins/plugin_context_impl.dart';
import '../providers/plugin_engine_provider.dart';
import '../providers/plugin_provider.dart';
import '../services/ssh_service.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import '../models/shell_profile.dart';
import '../providers/settings_provider.dart';
import '../providers/terminal_layout_provider.dart';
import '../services/hotkey_service.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../widgets/script_plugin_panel_screen.dart';
import '../providers/share_provider.dart';
import '../widgets/share_session_dialog.dart';
import '../widgets/join_share_dialog.dart';
import '../widgets/update_banner.dart';
import '../widgets/notification_bell.dart';
import '../widgets/session_tab.dart';
import '../models/rdp_session.dart';
import '../widgets/rdp_workspace.dart';
import '../models/vnc_session.dart';
import '../widgets/vnc_workspace.dart';
import '../services/storage_service.dart';

enum NavSection { mcp, notes, hosts, keychain, portForwarding, sftp, knownHosts, recordings, audit, settings, plugins }

enum _SidePanel { none, host, newGroup, import }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final _workspaceSvc = WorkspaceService();
  Timer? _workspaceSaveDebounce;
  NavSection _nav = NavSection.hosts;
  String? _activePluginId;
  String? _activeScriptPanel;
  bool _pluginResetScheduled = false;
  _SidePanel _sidePanel = _SidePanel.none;
  final Map<String, PluginContextImpl> _pluginContexts = {};
  Host? _editingHost;
  String? _initialGroup;
  HostProtocol _initialProtocol = HostProtocol.ssh;
  bool _viewingTerminal = false;
  Set<String> _observedSessionIds = {};
  bool _showAiChat = false;
  final _sftpConnectionNotifier = ValueNotifier<bool>(false);
  SessionProvider? _sessionProvider;
  KnownHostsProvider? _knownHostsProvider;
  SettingsProvider? _settingsProvider;
  TerminalLayoutProvider? _layoutProvider;
  bool _hostKeyDialogShowing = false;
  bool _rdpCertDialogShowing = false;
  bool _consentDialogShowing = false;
  bool _rdpFullscreen = false;
  bool _vncFullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreWorkspace());
    _sftpConnectionNotifier.addListener(_onSftpConnectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wirePluginLifecycle();
      _wireRecordingErrors();
    });
  }

  void _showUpdateDetails() => setState(() {
        _activePluginId = null;
        _activeScriptPanel = null;
        _nav = NavSection.settings;
        _viewingTerminal = false;
        _showAiChat = false;
      });

  void _wireRecordingErrors() {
    if (!mounted) return;
    context.read<RecordingProvider>().onStartFailed = (session, error) {
      if (!mounted) return;
      AppSnack.error(context, LMessage('Recording failed for {0}: {1}', [session.tabLabel, error]));
    };
  }

  void _wirePluginLifecycle() {
    if (!mounted) return;
    final pluginProvider = context.read<PluginProvider>();
    // Catch per-plugin so one buggy plugin can't take down the whole toggle.
    pluginProvider.onToggled = (plugin, enabled) {
      try {
        if (enabled) {
          plugin.onActivate(_pluginContext(plugin.id));
        } else {
          plugin.onDeactivate();
        }
      } catch (e, st) {
        debugPrint('[plugin ${plugin.id}] lifecycle error: $e\n$st');
      }
    };
    // Fire onActivate for plugins already enabled at startup (prefs already loaded).
    for (final plugin in pluginProvider.enabledPlugins) {
      try {
        plugin.onActivate(_pluginContext(plugin.id));
      } catch (e, st) {
        debugPrint('[plugin ${plugin.id}] onActivate error: $e\n$st');
      }
    }
  }

  Future<void> _registerHotkeys(Map<String, String> hotkeys) async {
    final svc = HotkeyService();
    await svc.unregisterAll();
    for (final entry in hotkeys.entries) {
      final hotKey = HotkeyService.parse(entry.value);
      if (hotKey == null) continue;
      await svc.register(entry.key, hotKey, () => _handleHotkey(entry.key));
    }
  }

  void _handleHotkey(String name) {
    if (!mounted) return;
    // Terminal-only features no-op on RDP tabs: their layout state is global
    // and persisted, so firing them against a remote-desktop tab would
    // corrupt the workspace snapshot restored on next launch.
    final isTerminal =
        context.read<SessionProvider>().activeSession is TerminalSession;
    switch (name) {
      case 'new_session':
        _openHostPanel();
      case 'close_session':
        context.read<SessionProvider>().closeActive();
      case 'next_session':
        context.read<SessionProvider>().activateNext();
      case 'prev_session':
        context.read<SessionProvider>().activatePrev();
      case 'toggle_input_bar':
        if (isTerminal) {
          context.read<TerminalLayoutProvider>().toggleInputBar();
        }
      case 'split_horizontal':
        if (isTerminal) {
          context.read<TerminalLayoutProvider>().setLayout(SplitLayout.horizontal);
        }
      case 'split_vertical':
        if (isTerminal) {
          context.read<TerminalLayoutProvider>().setLayout(SplitLayout.vertical);
        }
      case 'command_palette':
        _openCommandPalette();
    }
  }

  void _onSftpConnectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<SessionProvider>();
    if (_sessionProvider != provider) {
      _sessionProvider?.removeListener(_onSessionsChanged);
      _sessionProvider?.removeListener(_onSessionsChangedForSave);
      _sessionProvider = provider;
      provider.addListener(_onSessionsChanged);
      provider.addListener(_onSessionsChangedForSave);
    }
    final settings = context.read<SettingsProvider>();
    if (_settingsProvider != settings) {
      _settingsProvider?.removeListener(_onSettingsChanged);
      _settingsProvider = settings;
      settings.addListener(_onSettingsChanged);
      _registerHotkeys(settings.hotkeys);
    }
    final knownHostsProvider = context.read<KnownHostsProvider>();
    if (_knownHostsProvider != knownHostsProvider) {
      _knownHostsProvider?.removeListener(_onKnownHostsChanged);
      _knownHostsProvider = knownHostsProvider;
      knownHostsProvider.addListener(_onKnownHostsChanged);
    }
    final layout = context.read<TerminalLayoutProvider>();
    if (_layoutProvider != layout) {
      _layoutProvider?.removeListener(_onLayoutChangedForSave);
      _layoutProvider = layout;
      layout.addListener(_onLayoutChangedForSave);
    }
  }

  void _onSettingsChanged() {
    if (_settingsProvider != null) {
      _registerHotkeys(_settingsProvider!.hotkeys);
    }
  }

  void _onKnownHostsChanged() {
    // isResolved guard: a settled challenge can linger on the provider until
    // its awaiting caller resumes — never re-show a dialog for it.
    final challenge = _knownHostsProvider?.pendingChallenge;
    if (challenge != null &&
        !challenge.isResolved &&
        !_hostKeyDialogShowing &&
        mounted) {
      _hostKeyDialogShowing = true;
      showSshHostKeyDialog(context, challenge).then((_) {
        _hostKeyDialogShowing = false;
        // A challenge raised while this dialog was open was skipped by the
        // guard above — re-check, or it would silently time out (2 min).
        scheduleMicrotask(_onKnownHostsChanged);
      });
    }

    final rdpChallenge = _knownHostsProvider?.pendingRdpChallenge;
    if (rdpChallenge != null &&
        !rdpChallenge.isResolved &&
        !_rdpCertDialogShowing &&
        mounted) {
      _rdpCertDialogShowing = true;
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RdpCertDialog(challenge: rdpChallenge),
      ).then((trusted) {
        rdpChallenge.resolve(trusted ?? false);
        _rdpCertDialogShowing = false;
        scheduleMicrotask(_onKnownHostsChanged);
      });
    }
  }

  void _onSessionsChanged() {
    if (!mounted) return;
    final sessions = _sessionProvider?.sessions ?? [];
    final ids = sessions.map((session) => session.id).toSet();
    final hasNewSession = ids.difference(_observedSessionIds).isNotEmpty;
    _observedSessionIds = ids;
    if (hasNewSession && !_viewingTerminal) {
      setState(() => _viewingTerminal = true);
    } else if (sessions.isEmpty && _viewingTerminal) {
      setState(() => _viewingTerminal = false);
    }
  }

  void _onLayoutChangedForSave() => _scheduleSave();
  void _onSessionsChangedForSave() => _scheduleSave();

  void _scheduleSave() {
    _workspaceSaveDebounce?.cancel();
    _workspaceSaveDebounce = Timer(
      const Duration(milliseconds: 500),
      _saveWorkspaceNow,
    );
  }

  /// Host id a session restores from, or null for ephemeral tabs (local
  /// shells, watch sessions).
  static String? _restorableHostId(AppSession s) => switch (s) {
        SshSession ssh => ssh.isWatch ? null : ssh.host.id,
        RdpSession rdp => rdp.host.id,
        VncSession vnc => vnc.host.id,
        _ => null,
      };

  void _saveWorkspaceNow() {
    // SSH + RDP tabs — local sessions are ephemeral by design.
    final provider = _sessionProvider;
    final layout = _layoutProvider;
    if (provider == null || layout == null) return;
    final active = provider.activeSession;
    final snapshot = WorkspaceSnapshot(
      hostIds: provider.sessions
          .map(_restorableHostId)
          .whereType<String>()
          .toList(),
      activeHostId: active == null ? null : _restorableHostId(active),
      layout: layout.layout,
      inputBarVisible: layout.inputBarVisible,
    );
    _workspaceSvc.save(snapshot);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) _saveWorkspaceNow();
  }

  @override
  void dispose() {
    _sftpConnectionNotifier.removeListener(_onSftpConnectionChanged);
    _sftpConnectionNotifier.dispose();
    _sessionProvider?.removeListener(_onSessionsChanged);
    _sessionProvider?.removeListener(_onSessionsChangedForSave);
    _knownHostsProvider?.removeListener(_onKnownHostsChanged);
    _settingsProvider?.removeListener(_onSettingsChanged);
    _layoutProvider?.removeListener(_onLayoutChangedForSave);
    WidgetsBinding.instance.removeObserver(this);
    _workspaceSaveDebounce?.cancel();
    HotkeyService().unregisterAll();
    super.dispose();
  }

  void _openHostPanel({Host? existing, String? initialGroup, HostProtocol protocol = HostProtocol.ssh}) {
    setState(() {
      _sidePanel = _SidePanel.host;
      _editingHost = existing;
      _initialGroup = initialGroup;
      _initialProtocol = protocol;
    });
  }

  /// Sidebar "Local Terminal" + command palette entry: focus the last local
  /// tab if one exists (list order approximates recency), else open a new one.
  void _openLocalTerminal() {
    final provider = context.read<SessionProvider>();
    final existing = provider.sessions.whereType<LocalSession>().lastOrNull;
    if (existing != null) {
      provider.setActive(existing.id);
    } else {
      unawaited(provider.newLocalSession());
    }
    setState(() => _viewingTerminal = true);
  }

  void _openNewGroupPanel() => setState(() {
        _sidePanel = _SidePanel.newGroup;
        _editingHost = null;
        _initialGroup = null;
      });

  void _openImportPanel() => setState(() {
        _sidePanel = _SidePanel.import;
        _editingHost = null;
        _initialGroup = null;
      });

  void _closePanel() => setState(() {
        _sidePanel = _SidePanel.none;
        _editingHost = null;
        _initialGroup = null;
      });

  Future<void> _restoreWorkspace() async {
    final snapshot = await _workspaceSvc.load();
    if (snapshot == null || !mounted) return;

    final hostProvider = context.read<HostProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final layoutProvider = context.read<TerminalLayoutProvider>();

    final allHosts = hostProvider.allHosts;
    final found = snapshot.hostIds
        .map((id) => allHosts.where((h) => h.id == id).firstOrNull)
        .whereType<Host>()
        .toList();

    final missingCount = snapshot.hostIds.length - found.length;
    if (missingCount > 0 && mounted) {
      AppSnack.info(context,
          LMessage('{0} host(s) from last session no longer exist', [missingCount]));
    }

    if (found.isEmpty) {
      await _workspaceSvc.clear();
      return;
    }

    layoutProvider.setLayout(snapshot.layout);
    if (snapshot.inputBarVisible != layoutProvider.inputBarVisible) {
      layoutProvider.toggleInputBar();
    }

    for (final host in found) {
      unawaited(sessionProvider.connectAny(host));
    }

    // Sessions are added synchronously at connect() entry; set active now.
    // (connectRdp has awaits before adding, so RDP tabs may land later —
    // the .last fallback in activeSession covers that gracefully.)
    if (snapshot.activeHostId != null) {
      final targetSession = sessionProvider.sessions
          .where((s) => _restorableHostId(s) == snapshot.activeHostId)
          .firstOrNull;
      if (targetSession != null) {
        sessionProvider.setActive(targetSession.id);
      }
    }

    await _workspaceSvc.clear();
  }

  void _openCommandPalette() {
    final hosts = context.read<HostProvider>().allHosts;
    final canShare = context.read<ShareProvider>().canShare;

    final items = <CommandItem>[
      // Actions
      CommandItem(
        id: 'action_new_host',
        title: tr(context, 'New Host'),
        subtitle: tr(context, 'Add a new SSH connection'),
        icon: Icons.add_circle_outline,
        type: CommandType.action,
        execute: () => WidgetsBinding.instance.addPostFrameCallback((_) => _openHostPanel()),
      ),
      CommandItem(
        id: 'action_import',
        title: tr(context, 'Import SSH Config'),
        subtitle: tr(context, 'Import from ~/.ssh/config'),
        icon: Icons.upload_file_outlined,
        type: CommandType.action,
        execute: () => WidgetsBinding.instance.addPostFrameCallback((_) => _openImportPanel()),
      ),
      if (canShare)
        CommandItem(
          id: 'action_join_share',
          title: tr(context, 'Join Shared Session'),
          subtitle: tr(context, 'Watch a colleague\'s terminal using a share code'),
          icon: Icons.screen_share_outlined,
          type: CommandType.action,
          execute: () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => showDialog(context: context, builder: (_) => const JoinShareDialog()),
          ),
        ),
      // Nav sections
      CommandItem(
        id: 'nav_hosts',
        title: tr(context, '连接'),
        subtitle: tr(context, 'Manage SSH connections'),
        icon: Icons.dns_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.hosts; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_sftp',
        title: tr(context, 'SFTP'),
        subtitle: tr(context, 'File transfer'),
        icon: Icons.folder_open,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.sftp; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_keychain',
        title: tr(context, '密钥与凭据'),
        subtitle: tr(context, 'SSH keys'),
        icon: Icons.vpn_key_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.keychain; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_port_forwarding',
        title: tr(context, '端口转发'),
        subtitle: tr(context, 'Tunnel rules'),
        icon: Icons.swap_horiz,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.portForwarding; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_local_terminal',
        title: tr(context, '本地终端'),
        subtitle: tr(context, 'Local shell'),
        icon: Icons.laptop_mac,
        type: CommandType.navSection,
        execute: _openLocalTerminal,
      ),
      CommandItem(
        id: 'nav_recordings',
        title: tr(context, '终端录制'),
        subtitle: tr(context, 'Session recordings'),
        icon: Icons.video_library_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.recordings; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_known_hosts',
        title: tr(context, '可信主机'),
        subtitle: tr(context, 'Host key verification'),
        icon: Icons.fact_check_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.knownHosts; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_settings',
        title: tr(context, '设置'),
        subtitle: tr(context, 'App preferences'),
        icon: Icons.settings_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.settings; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_plugins',
        title: tr(context, '扩展工具'),
        subtitle: tr(context, 'Plugin marketplace'),
        icon: Icons.extension_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.plugins; _viewingTerminal = false; }),
      ),
      // Hosts
      ...hosts.map((h) => CommandItem(
        id: 'host_${h.id}',
        title: h.label,
        subtitle: tr(context, '${h.username}@${h.host}:${h.port}'),
        icon: Icons.dns,
        type: CommandType.host,
        execute: () async {
          setState(() => _viewingTerminal = true);
          await context.read<SessionProvider>().connectAny(h);
        },
      )),
    ];

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => CommandPaletteDialog(items: items),
    );
  }

  PluginContextImpl _pluginContext(String pluginId) {
    return _pluginContexts.putIfAbsent(pluginId, () => PluginContextImpl(
      sessions: context.read<SessionProvider>(),
      ssh: context.read<SshService>(),
      pluginId: pluginId,
    ));
  }

  /// Enters/exits RDP fullscreen: OS window fullscreen + the app chrome
  /// (tab bar, sidebar, panels) collapses to just the RdpWorkspace.
  Future<void> _setRdpFullscreen(bool on) async {
    if (_rdpFullscreen == on || !mounted) return;
    setState(() => _rdpFullscreen = on);
    try {
      await windowManager.setFullScreen(on);
    } catch (_) {
      // Window manager unavailable (tests/headless) — chrome state already
      // applied, which is the part that matters for correctness.
    }
  }

  /// Enters/exits VNC fullscreen: mirrors _setRdpFullscreen exactly.
  Future<void> _setVncFullscreen(bool on) async {
    if (_vncFullscreen == on || !mounted) return;
    setState(() => _vncFullscreen = on);
    try {
      await windowManager.setFullScreen(on);
    } catch (_) {
      // Window manager unavailable (tests/headless) — chrome state applied.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionProvider = context.watch<SessionProvider>();
    final sessions = sessionProvider.sessions;
    final activeSession = sessionProvider.activeSession;

    // Fullscreen only makes sense while an RDP tab is front-and-center;
    // anything that breaks that (tab switched via hotkey, tab closed, nav
    // changed) drops back to windowed mode instead of trapping the user in
    // a chrome-less screen.
    final rdpFullscreenActive =
        _rdpFullscreen && _viewingTerminal && activeSession is RdpSession;
    if (_rdpFullscreen && !rdpFullscreenActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_setRdpFullscreen(false));
      });
    }
    if (rdpFullscreenActive) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: _buildForeground(activeSession),
      );
    }

    final vncFullscreenActive =
        _vncFullscreen && _viewingTerminal && activeSession is VncSession;
    if (_vncFullscreen && !vncFullscreenActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_setVncFullscreen(false));
      });
    }
    if (vncFullscreenActive) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: _buildForeground(activeSession),
      );
    }

    final engineProvider = context.watch<PluginEngineProvider>();
    if (engineProvider.pendingConsent != null && !_consentDialogShowing) {
      _consentDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              PluginConsentDialog(manifest: engineProvider.pendingConsent!),
        ).then((_) => setState(() => _consentDialogShowing = false));
      });
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _TopTabBar(
            sessions: sessions,
            active: activeSession,
            nav: _nav,
            viewingTerminal: _viewingTerminal && sessions.isNotEmpty,
            onNavSelect: (s) => setState(() {
              _activePluginId = null;
              _activeScriptPanel = null;
              _nav = s;
              _viewingTerminal = false;
              _showAiChat = false;
              if (s != NavSection.hosts) _closePanel();
            }),
            onSessionTap: (_) => setState(() => _viewingTerminal = true),
            onAddSession: () {
              setState(() {
                _activePluginId = null;
                _activeScriptPanel = null;
                _nav = NavSection.hosts;
                _viewingTerminal = false;
                _showAiChat = false;
              });
              _openHostPanel();
            },
            onAddLocalSession: (
                {ShellProfile? profile, bool platformDefault = false}) {
              setState(() => _viewingTerminal = true);
              unawaited(context.read<SessionProvider>().newLocalSession(
                  profile: profile, platformDefault: platformDefault));
            },
            onShowUpdateDetails: _showUpdateDetails,
            onOpenSession: (sessionId) {
              final sp = context.read<SessionProvider>();
              if (sp.sessions.any((s) => s.id == sessionId)) {
                sp.setActive(sessionId);
                setState(() => _viewingTerminal = true);
              }
            },
          ),
          UpdateBanner(onShowDetails: _showUpdateDetails),

          Expanded(
            child: Row(
              children: [
                if (_nav != NavSection.hosts && _nav != NavSection.notes &&
                    (!_viewingTerminal || sessions.isEmpty) &&
                    !(_nav == NavSection.sftp && _sftpConnectionNotifier.value))
                  _Sidebar(
                    selected: _nav,
                    activePluginId: _activePluginId,
                    onOpenLocalTerminal: _openLocalTerminal,
                    onSelect: (s) {
                      if (s != NavSection.hosts) _closePanel();
                      setState(() {
                        _activePluginId = null;
                        _activeScriptPanel = null;
                        _nav = s;
                        _viewingTerminal = false;
                        _showAiChat = false;
                      });
                    },
                    onSelectPlugin: (id) {
                      setState(() {
                        _activePluginId = id;
                        _viewingTerminal = false;
                        _sidePanel = _SidePanel.none;
                      });
                    },
                    activeScriptPanel: _activeScriptPanel,
                    onSelectScriptPanel: (pluginId) {
                      setState(() {
                        _activeScriptPanel = pluginId;
                        _activePluginId = null;
                        _viewingTerminal = false;
                        _sidePanel = _SidePanel.none;
                      });
                    },
                  ),
                Expanded(child: _buildContent(activeSession)),
                if (_nav == NavSection.hosts && !_viewingTerminal) ...[
                  if (_sidePanel == _SidePanel.host)
                    HostDetailPanel(
                      existing: _editingHost,
                      initialGroup: _initialGroup,
                      initialProtocol: _initialProtocol,
                      onClose: _closePanel,
                      onSave: (host, password) async {
                        final hp = context.read<HostProvider>();
                        if (_editingHost != null) {
                          await hp.updateHost(host, password: password);
                        } else {
                          await hp.addHost(host, password: password);
                        }
                      },
                      onConnect: (host) async {
                        setState(() => _viewingTerminal = true);
                        unawaited(context.read<SessionProvider>().connectAny(host));
                      },
                    ),
                  if (_sidePanel == _SidePanel.newGroup)
                    NewGroupPanel(onClose: _closePanel),
                  if (_sidePanel == _SidePanel.import)
                    ImportPanel(onClose: _closePanel),
                ],
              ],
            ),
          ),
          Consumer<PluginUiRegistry>(
            builder: (context, registry, _) {
              if (registry.statusBarItems.isEmpty) return const SizedBox.shrink();
              return Container(
                height: 24,
                color: AppColors.sidebar,
                child: Row(
                  children: [
                    for (final item in registry.statusBarItems)
                      Tooltip(
                        message: item.tooltip ?? '',
                        child: InkWell(
                          onTap: item.onClick,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              item.label,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppSession? active) {
    final showTerminal = _viewingTerminal && active is TerminalSession;
    final showHosts = _nav == NavSection.hosts && !(_viewingTerminal && active != null) &&
        _activePluginId == null && _activeScriptPanel == null;
    final showSftp = _nav == NavSection.sftp &&
        !(_viewingTerminal && active != null) &&
        _activePluginId == null &&
        _activeScriptPanel == null;

    return Stack(
      fit: StackFit.expand,
      children: [
        KeepAliveOffstage(active: showHosts, child: ConnectionCenter(
          onSerialConnect: (device, config, backend) async {
            final provider = context.read<SessionProvider>();
            final previous = provider.activeSession;
            final opening = provider.connectSerial(device, config, backend);
            if (provider.activeSession != previous) setState(() => _viewingTerminal = true);
            await opening;
          },
          onAdd: (protocol, group) => _openHostPanel(protocol: protocol, initialGroup: group),
          onEdit: (host) => _openHostPanel(existing: host, protocol: host.protocol),
          onConnect: (host) async {
            setState(() => _viewingTerminal = true);
            unawaited(context.read<SessionProvider>().connectAny(host));
          },
          onNewGroup: () => _openNewGroupPanel(),
          onImport: _openImportPanel,
        )),
        // SFTP stays mounted (offstage) once opened so its connected session,
        // paths, and in-flight transfers survive switching tabs (issue #42).
        KeepAliveOffstage(
          active: showSftp,
          child: DualPanelSftpScreen(
            connectionNotifier: _sftpConnectionNotifier,
            active: showSftp,
          ),
        ),
        // Retain file providers, in-flight listings, and monitor history while
        // another navigation page or a non-terminal session is foreground.
        KeepAliveOffstage(
          key: const ValueKey('terminal-workspace'),
          active: showTerminal,
          child: _buildTerminalWorkspace(active),
        ),
        if (!showSftp && !showHosts && !showTerminal) _buildForeground(active),
      ],
    );
  }

  Widget _buildTerminalWorkspace(AppSession? active) {
    // Hide the AI toggle (and any open chat panel) when no AI provider
    // has an API key configured — it appears once a key is saved.
    final aiConfigured = context.select<AiChatProvider, bool>(
        (p) => p.configuredProviders.isNotEmpty);
    final showAiChat = _showAiChat && aiConfigured;
    return Row(
      children: [
        Expanded(
          child: Stack(
            children: [
              SplitTerminalView(
                onNavigateToSettings: () => setState(() {
                  _nav = NavSection.settings;
                  _viewingTerminal = false;
                }),
              ),
              Positioned(
                top: 8,
                right: showAiChat ? 348 : 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const NetworkStatsOverlay(),
                    if (active is SshSession) ...[
                      const SizedBox(width: 8),
                      _ShareButton(session: active),
                    ],
                    if (aiConfigured) ...[
                      const SizedBox(width: 8),
                      _AiChatToggle(
                        active: showAiChat,
                        onToggle: () =>
                            setState(() => _showAiChat = !_showAiChat),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showAiChat)
          AiChatSidebar(
            onClose: () => setState(() => _showAiChat = false),
          ),
      ],
    );
  }

  Widget _buildForeground(AppSession? active) {
    if (_viewingTerminal && active is SerialSession) {
      return SerialSessionPane(key: ValueKey(active.id), session: active);
    }
    if (_viewingTerminal && active is RdpSession) {
      return RdpWorkspace(
        session: active,
        onReconnect: () => _retryRdp(active),
        isFullscreen: _rdpFullscreen,
        onFullscreenChanged: (on) => unawaited(_setRdpFullscreen(on)),
      );
    }
    if (_viewingTerminal && active is VncSession) {
      return VncWorkspace(
        session: active,
        onReconnect: () => _retryVnc(active),
        isFullscreen: _vncFullscreen,
        onFullscreenChanged: (on) => unawaited(_setVncFullscreen(on)),
      );
    }

    // Script plugin panel
    if (_activeScriptPanel != null) {
      final registry = context.watch<PluginUiRegistry>();
      final panels = registry.panels.where((p) => p.pluginId == _activeScriptPanel);
      if (panels.isNotEmpty) {
        return ScriptPluginPanelScreen(panel: panels.first);
      }
      if (!_pluginResetScheduled) {
        _pluginResetScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pluginResetScheduled = false;
          if (mounted) setState(() => _activeScriptPanel = null);
        });
      }
      return const SizedBox.shrink();
    }

    // Active plugin view
    if (_activePluginId != null) {
      final pluginProvider = context.watch<PluginProvider>(); // watch so disable triggers rebuild
      final enabled = pluginProvider.enabledPlugins.where((p) => p.id == _activePluginId);
      if (enabled.isNotEmpty) {
        final plugin = enabled.first;
        return _PluginErrorBoundary(
          key: ValueKey(plugin.id),
          plugin: plugin,
          pluginCtx: _pluginContext(plugin.id),
        );
      }
      // Plugin was disabled while viewing it — reset once after this frame.
      // Without the guard, the post-frame callback re-runs every build, causing
      // an infinite rebuild loop until the plugin re-enables.
      if (!_pluginResetScheduled) {
        _pluginResetScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pluginResetScheduled = false;
          if (mounted) setState(() => _activePluginId = null);
        });
      }
      return const SizedBox.shrink();
    }

    return switch (_nav) {
      NavSection.notes => const NotesScreen(),
      NavSection.mcp => const McpScreen(),
      NavSection.hosts => const SizedBox.shrink(),
      NavSection.keychain => const KeychainScreen(),
      NavSection.portForwarding => const PortForwardingScreen(),
      // Rendered by the KeepAliveOffstage layer in _buildContent.
      NavSection.sftp => const SizedBox.shrink(),
      NavSection.recordings => const RecordingLibraryScreen(),
      NavSection.audit => const AuditScreen(),
      NavSection.knownHosts => const KnownHostsScreen(),
      NavSection.settings => const SettingsScreen(),
      NavSection.plugins => const PluginManagerScreen(),
    };
  }

  Future<void> _retryRdp(RdpSession old) async {
    final provider = context.read<SessionProvider>();
    if (old.status == RdpSessionStatus.error) {
      final newPassword = await showDialog<String>(
        context: context,
        builder: (_) => _RdpPasswordDialog(host: old.host),
      );
      if (newPassword == null) return; // cancelled
      if (!mounted) return;
      await context.read<StorageService>().savePassword(old.host.id, newPassword);
    }
    if (!mounted) return;
    await provider.reconnectRdp(old);
  }

  Future<void> _retryVnc(VncSession old) async {
    if (!mounted) return;
    await context.read<SessionProvider>().reconnectVnc(old);
  }
}

// ── Sidebar ───────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final NavSection selected;
  final String? activePluginId;
  final String? activeScriptPanel;
  final ValueChanged<NavSection> onSelect;
  final ValueChanged<String> onSelectPlugin;
  final ValueChanged<String> onSelectScriptPanel;
  final VoidCallback onOpenLocalTerminal;
  const _Sidebar({
    required this.selected,
    required this.activePluginId,
    required this.activeScriptPanel,
    required this.onSelect,
    required this.onSelectPlugin,
    required this.onSelectScriptPanel,
    required this.onOpenLocalTerminal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: AppColors.textSecondary, size: 16),
                const SizedBox(width: 8),
                const LText("waytty",
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),

          // Scrollable nav area so the sidebar never overflows when the
          // window is short or many plugin/script panels are enabled.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          const _SectionLabel('连接管理'),
          _navItem(Icons.dns_outlined, '连接', NavSection.hosts),
          _navItem(Icons.swap_horiz, '端口转发', NavSection.portForwarding),
          _navItem(Icons.fact_check_outlined, '可信主机', NavSection.knownHosts),

          const _SectionLabel('文件传输'),
          _navItem(Icons.folder_open, 'SFTP', NavSection.sftp),

          const _SectionLabel('工具'),
          // Action, not a nav target: local terminal lives in the top tab bar.
          _NavItem(
            icon: Icons.laptop_mac,
            label: tr(context, "本地终端"),
            selected: false,
            onTap: onOpenLocalTerminal,
          ),
          _navItem(Icons.video_library_outlined, '终端录制', NavSection.recordings),
          _navItem(Icons.receipt_long_outlined, '操作日志', NavSection.audit),
          _navItem(Icons.hub_outlined, 'MCP 服务', NavSection.mcp),
          ...context.watch<PluginProvider>().enabledPlugins.map(
            (plugin) => _pluginNavItem(context, plugin),
          ),
          ...context.watch<PluginUiRegistry>().panels.map(
            (panel) => _ScriptPanelNavItem(
              panel: panel,
              isActive: activeScriptPanel == panel.pluginId,
              onTap: () => onSelectScriptPanel(panel.pluginId),
            ),
          ),

          const _SectionLabel('SECURITY'),
          _navItem(Icons.vpn_key_outlined, '密钥与凭据', NavSection.keychain),

                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _navItem(Icons.extension_outlined, '扩展工具', NavSection.plugins),
          _navItem(Icons.settings_outlined, '设置', NavSection.settings),
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 28,
                    height: 28,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LText("waytty", style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
                    LText(LMessage("v{0}", [kAppVersion]), style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, NavSection section) {
    final isSelected = activePluginId == null && selected == section;
    return _NavItem(icon: icon, label: label, selected: isSelected, onTap: () => onSelect(section));
  }

  Widget _pluginNavItem(BuildContext context, YourSSHPlugin plugin) {
    return _PluginNavItem(
      plugin: plugin,
      isActive: activePluginId == plugin.id,
      onTap: () => onSelectPlugin(plugin.id),
    );
  }
}

class _PluginNavItem extends StatefulWidget {
  final YourSSHPlugin plugin;
  final bool isActive;
  final VoidCallback onTap;
  const _PluginNavItem({required this.plugin, required this.isActive, required this.onTap});

  @override
  State<_PluginNavItem> createState() => _PluginNavItemState();
}

class _PluginNavItemState extends State<_PluginNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isActive
        ? AppColors.accent.withValues(alpha: 0.12)
        : _hovered
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent;
    final iconColor = widget.isActive ? AppColors.accent : AppColors.textSecondary;
    final textColor = widget.isActive ? AppColors.accent : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.isActive ? Border.all(color: AppColors.accent.withValues(alpha: 0.2)) : null,
          ),
          child: Row(
            children: [
              Icon(widget.plugin.icon, size: 15, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: LText(
                  widget.plugin.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScriptPanelNavItem extends StatelessWidget {
  final PluginPanelEntry panel;
  final bool isActive;
  final VoidCallback onTap;

  const _ScriptPanelNavItem({
    required this.panel,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _NavItem(
      icon: Icons.code_outlined,
      label: panel.title,
      selected: isActive,
      onTap: onTap,
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? AppColors.accent.withValues(alpha: 0.12)
        : _hovered
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent;
    final iconColor = widget.selected ? AppColors.accent : AppColors.textSecondary;
    final textColor = widget.selected ? AppColors.accent : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.selected ? Border.all(color: AppColors.accent.withValues(alpha: 0.2)) : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: iconColor),
              const SizedBox(width: 10),
              LText(widget.label, style: TextStyle(color: textColor, fontSize: 13, fontWeight: widget.selected ? FontWeight.w500 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Top Tab Bar ───────────────────────────────────────────

class _TopTabBar extends StatelessWidget {
  final List<AppSession> sessions;
  final AppSession? active;
  final NavSection nav;
  final bool viewingTerminal;
  final ValueChanged<NavSection> onNavSelect;
  final ValueChanged<String> onSessionTap;
  final VoidCallback onAddSession;
  final void Function({ShellProfile? profile, bool platformDefault})
      onAddLocalSession;
  final VoidCallback onShowUpdateDetails;
  final ValueChanged<String> onOpenSession;

  const _TopTabBar({
    required this.sessions,
    required this.active,
    required this.nav,
    required this.viewingTerminal,
    required this.onNavSelect,
    required this.onSessionTap,
    required this.onAddSession,
    required this.onAddLocalSession,
    required this.onShowUpdateDetails,
    required this.onOpenSession,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SessionProvider>();
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: DragToMoveArea(child: Row(
        children: [
          if (Platform.isMacOS) const SizedBox(width: 78),
          // Pinned nav shortcuts
          _PinnedTab(
            icon: Icons.home_outlined,
            label: tr(context, "连接"),
            active: nav == NavSection.hosts && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.hosts),
          ),
          _PinnedTab(
            icon: Icons.folder_outlined,
            label: tr(context, "SFTP"),
            active: nav == NavSection.sftp && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.sftp),
          ),
          _PinnedTab(icon: Icons.terminal, label: tr(context, "本地终端"), active: false,
            onTap: () => onAddLocalSession()),
          _PinnedTab(icon: Icons.description_outlined, label: tr(context, "笔记"),
            active: nav == NavSection.notes && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.notes)),
          _PinnedTab(icon: Icons.grid_view, label: tr(context, "工具"),
            active: nav == NavSection.plugins && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.plugins)),
          // Divider
          Container(width: 1, height: 18, color: const Color(0xFF2A2A2A)),
          const SizedBox(width: 4),
          // Session tabs (scrollable, drag-reorderable)
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: sessions.length,
              onReorderItem: provider.reorderSessionItem,
              itemBuilder: (context, index) {
                final s = sessions[index];
                return ReorderableDragStartListener(
                  key: ValueKey(s.id),
                  index: index,
                  child: SessionTab(
                    session: s,
                    isActive: s.id == active?.id && viewingTerminal,
                    provider: provider,
                    onTap: () => onSessionTap(s.id),
                  ),
                );
              },
            ),
          ),
          // "+" button
          _AddTabBtn(onNewSsh: onAddSession, onNewLocal: onAddLocalSession),
          IconButton(tooltip: tr(context, "设置"), icon: const Icon(Icons.settings_outlined, size: 16),
            onPressed: () => onNavSelect(NavSection.settings)),
          NotificationBellBtn(
            onShowUpdateDetails: onShowUpdateDetails,
            onOpenSession: onOpenSession,
          ),
        ],
      )),
    );
  }
}

class _PinnedTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PinnedTab({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  State<_PinnedTab> createState() => _PinnedTabState();
}

class _PinnedTabState extends State<_PinnedTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? AppColors.accent
        : _hovered
            ? const Color(0xFFAAAAAA)
            : const Color(0xFF666666);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: widget.active
                ? const Border(bottom: BorderSide(color: AppColors.accent, width: 2))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 6),
              LText(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: widget.active ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTabBtn extends StatefulWidget {
  final VoidCallback onNewSsh;
  final void Function({ShellProfile? profile, bool platformDefault})
      onNewLocal;
  const _AddTabBtn({required this.onNewSsh, required this.onNewLocal});

  @override
  State<_AddTabBtn> createState() => _AddTabBtnState();
}

class _AddTabBtnState extends State<_AddTabBtn> {
  bool _hovered = false;

  Future<void> _showAddMenu() async {
    // Same set as the Settings dropdown: platform default + detected + custom.
    final profiles = context.read<SettingsProvider>().allShellProfiles;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset(0, box.size.height));
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          origin.dx, origin.dy, origin.dx + 1, origin.dy + 1),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        const PopupMenuItem(
          value: 'ssh',
          child: Row(children: [
            Icon(Icons.dns_outlined, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            LText("新建 SSH 连接",
                style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
        const PopupMenuItem(
          value: 'local',
          child: Row(children: [
            Icon(Icons.laptop_mac, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            LText("新建本地终端",
                style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
        if (profiles.isNotEmpty) const PopupMenuDivider(height: 4),
        if (profiles.isNotEmpty)
          const PopupMenuItem(
            value: 'shell:$kPlatformDefaultShellId',
            child: Row(children: [
              Icon(Icons.terminal, size: 14, color: Color(0xFFAAAAAA)),
              SizedBox(width: 8),
              LText("Platform default shell",
                  style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
            ]),
          ),
        for (final s in profiles)
          PopupMenuItem(
            value: 'shell:${s.id}',
            child: Row(children: [
              const Icon(Icons.terminal, size: 14, color: Color(0xFFAAAAAA)),
              const SizedBox(width: 8),
              Text(s.name,
                  style: const TextStyle(
                      color: Color(0xFFCCCCCC), fontSize: 13)),
            ]),
          ),
      ],
    );
    if (result == null) return;
    if (result == 'ssh') {
      widget.onNewSsh();
    } else if (result == 'local') {
      widget.onNewLocal();
    } else if (result == 'shell:$kPlatformDefaultShellId') {
      widget.onNewLocal(platformDefault: true);
    } else if (result.startsWith('shell:')) {
      final id = result.substring('shell:'.length);
      widget.onNewLocal(profile: profiles.firstWhere((s) => s.id == id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _showAddMenu,
        child: Container(
          width: 36,
          height: 38,
          alignment: Alignment.center,
          child: Icon(
            Icons.add,
            size: 16,
            color: _hovered ? const Color(0xFFAAAAAA) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

// ── AI Chat Toggle Button ─────────────────────────────────

class _AiChatToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onToggle;

  const _AiChatToggle({required this.active, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr(context, active ? "Close AI Chat" : "Open AI Chat"),
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.15)
                : AppColors.card.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 14,
                color: active ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              LText(
                "AI",
                style: TextStyle(
                  color: active ? AppColors.accent : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Host Key Mismatch Dialog ──────────────────────────────

/// Chrome for the RDP certificate trust prompt.
class _TofuDialog extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String endpoint;
  final List<Widget> fingerprintRows;
  final String warning;
  final String cancelLabel;
  final String acceptLabel;

  const _TofuDialog({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.endpoint,
    required this.fingerprintRows,
    required this.warning,
    required this.cancelLabel,
    required this.acceptLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(icon, color: accentColor, size: 20),
          const SizedBox(width: 8),
          LText(title,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 15)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(endpoint,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          ...fingerprintRows,
          const SizedBox(height: 12),
          LText(warning,
              style: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 11)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: LText(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: accentColor),
          child: LText(acceptLabel),
        ),
      ],
    );
  }
}

// ── RDP Certificate TOFU Dialog ───────────────────────────

class _RdpCertDialog extends StatelessWidget {
  final RdpCertChallenge challenge;
  const _RdpCertDialog({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final mismatch = challenge.isMismatch;
    return _TofuDialog(
      icon: mismatch ? Icons.warning_amber_rounded : Icons.lock_open,
      accentColor: mismatch ? AppColors.red : AppColors.accent,
      title: tr(context, mismatch ? "RDP certificate changed" : "Trust RDP certificate?"),
      endpoint: '${challenge.host}:${challenge.port}',
      fingerprintRows: [
        _FpRow(label: tr(context, "SHA-256"), fp: challenge.fingerprint),
      ],
      warning: mismatch
          ? 'The server certificate has changed since you last connected. '
              'This could indicate a man-in-the-middle attack. The connection '
              'was aborted before your credentials were sent.'
          : 'This server\'s certificate is not yet trusted. '
              'Verify the fingerprint above before accepting.',
      cancelLabel: tr(context, "Reject"),
      acceptLabel: mismatch ? 'Trust new cert' : 'Accept',
    );
  }
}

// ── Plugin Error Boundary ─────────────────────────────────

class _PluginErrorBoundary extends StatefulWidget {
  final YourSSHPlugin plugin;
  final PluginContextImpl pluginCtx;
  const _PluginErrorBoundary({super.key, required this.plugin, required this.pluginCtx});

  @override
  State<_PluginErrorBoundary> createState() => _PluginErrorBoundaryState();
}

class _PluginErrorBoundaryState extends State<_PluginErrorBoundary> {
  Object? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 12),
              LText(
                LMessage("Plugin crashed: {0}", [_error]),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    try {
      return widget.plugin.buildUI(context, widget.pluginCtx);
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _error = e);
      });
      return const SizedBox.shrink();
    }
  }

  @override
  void didUpdateWidget(_PluginErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugin.id != widget.plugin.id) _error = null;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: LText(
        text,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _FpRow extends StatelessWidget {
  final String label;
  final String fp;
  const _FpRow({required this.label, required this.fp});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          // Wide enough for 'SHA-256:' — 34px wrapped it mid-label.
          width: 60,
          child: LText(LMessage("{0}:", [label]),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ),
        Expanded(
          child: Text(fp,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace')),
        ),
      ],
    );
  }
}

class _ShareButton extends StatelessWidget {
  final SshSession session;
  const _ShareButton({required this.session});

  @override
  Widget build(BuildContext context) {
    final share = context.watch<ShareProvider>();
    if (!share.canShare || session.isWatch) return const SizedBox.shrink();
    if (session.status != SessionStatus.connected) return const SizedBox.shrink();

    final isActive = share.isSharing;
    return Tooltip(
      message: tr(context, isActive ? "Sharing active" : "Share this terminal"),
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => ShareSessionDialog(sessionId: session.id),
        ),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accent.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? AppColors.accent : const Color(0xFF2A2A2A),
            ),
          ),
          child: Icon(
            Icons.screen_share_outlined,
            size: 14,
            color: isActive ? AppColors.accent : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

// ── RDP password re-prompt dialog ─────────────────────────

class _RdpPasswordDialog extends StatefulWidget {
  final Host host;
  const _RdpPasswordDialog({required this.host});

  @override
  State<_RdpPasswordDialog> createState() => _RdpPasswordDialogState();
}

class _RdpPasswordDialogState extends State<_RdpPasswordDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: LText(LMessage("Password for {0}", [widget.host.label])),
      content: TextField(
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration:  InputDecoration(labelText: tr(context, "Password")),
        onSubmitted: (_) => Navigator.pop(context, _ctrl.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const LText("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const LText("Connect"),
        ),
      ],
    );
  }
}

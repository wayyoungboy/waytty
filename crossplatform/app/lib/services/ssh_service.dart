import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'bounded_ssh_exec.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import 'osc52_clipboard.dart';
import '../providers/shell_integration_provider.dart';
import '../models/agent_forwarding_state.dart';
import '../models/host.dart';
import '../models/proxy_settings.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import '../models/ssh_credentials.dart';
import '../models/ssh_connection_attempt.dart';
import 'manual_ssh_identity.dart';
import 'local_ssh_key_store.dart';
import 'connection_proxy.dart';
import 'proxy_handshake.dart';
import 'injection_gate.dart';
import '../models/audit_event.dart';
import 'audit_service.dart';
import 'notification_service.dart';
import 'shell_integration_service.dart';
import 'recording_service.dart';
import 'os_detection.dart';
import 'storage_service.dart';
import 'sudo_sftp.dart';
import 'system_agent_proxy.dart';

/// One hop in a jump chain: the bastion host plus its resolved key.
typedef JumpHop = ({Host host, SshKeyEntry? keyEntry});

/// A jump chain that cannot be built or dialed for a **configuration**
/// reason — a hop id that no longer resolves, a cycle, the target inside
/// its own chain. Distinct from a transient network failure: callers must
/// NOT auto-retry it (retrying a deleted bastion loops forever).
class JumpChainException implements Exception {
  final String message;
  JumpChainException(this.message);
  @override
  String toString() => 'JumpChainException: $message';
}

class SshService {
  final StorageService _storage;
  Future<void> Function(Host host)? privateKeyEditor;
  LocalSshKeyStore get savedPrivateKeys => _storage.privateKeys;
  final HookBus? hookBus;
  final ShellIntegrationProvider? shellIntegration;

  /// Audit trail sink; null disables auditing (tests, early startup).
  AuditService? audit;

  /// Global on/off for shell integration, read from SettingsProvider in
  /// main.dart. null => treat as enabled.
  bool Function()? isShellIntegrationEnabled;
  final Map<String, SSHClient> _clients = {};
  final Map<String, Future<SSHClient>> _connecting = {};

  final Map<String, Set<SshConnectionAttempt>> _attempts = {};
  final Map<String, SshConnectionAttempt> _hopAttempts = {};
  final Map<String, ({String hostId, SshConnectionAttempt attempt})> _openingShells = {};

  Future<SshCredentials?> Function(Host host, SshConnectionAttempt attempt)? credentialsPrompt;
  Future<String?> Function(Host host, SshConnectionAttempt attempt)? proxyPasswordPrompt;

  SshConnectionAttempt _beginAttempt(String hostId) {
    final attempt = SshConnectionAttempt();
    (_attempts[hostId] ??= {}).add(attempt);
    return attempt;
  }

  void _endAttempt(String hostId, SshConnectionAttempt attempt) {
    final attempts = _attempts[hostId];
    attempts?.remove(attempt);
    if (attempts?.isEmpty == true) _attempts.remove(hostId);
  }

  Future<bool> _verifyHostKey(Host host, String type, Uint8List fp,
      SshConnectionAttempt attempt,
      Future<bool> Function(String, Uint8List)? verify) async {
    try {
      attempt.check();
      final approved = await attempt.wait(verify != null
          ? verify(type, fp)
          : defaultHostKeyVerifier?.call(host.host, host.port, type, fp, attempt: attempt)
              ?? Future.value(false));
      return !attempt.isCancelled && approved;
    } catch (_) {
      // The transport expects a verdict (or an SSHError), not UI/cancellation
      // exceptions. Reject without leaking callback errors into the event loop.
      return false;
    }
  }

  Future<SshCredentials> _requestCredentials(Host host, SshConnectionAttempt attempt, {String? password}) async {
    attempt.check();
    if (host.authType == AuthType.password && password != null) {
      return SshCredentials(password: password);
    }
    final prompt = credentialsPrompt;
    if (prompt == null) throw const ManualAuthenticationRequired();
    final input = await attempt.wait(prompt(host, attempt));
    attempt.check();
    if (input == null) throw const AuthenticationCancelled();
    return input;
  }
  final Map<String, SSHSession> _shells = {};
  final Map<String, String> _shellToHost = {}; // sessionId → hostId
  final Map<String, SystemAgentProxy> _agentProxies = {};
  // Keyed by chain-prefix ('a' for hop0, 'a>b' for hop1 through a, …): a
  // client to B *through A* is distinct from a direct client to B. Proxies
  // share the same prefix key so teardown of one chain can't close a proxy
  // another chain still uses.
  final Map<String, SSHClient> _jumpClients = {};
  final Map<String, SystemAgentProxy> _jumpAgentProxies = {};
  // In-flight dials by prefix, so concurrent connects through the same
  // bastion reuse one dial instead of opening duplicates.
  final Map<String, Future<({SSHClient client, SystemAgentProxy? proxy})>>
      _jumpInflight = {};
  // target hostId → its chain-prefix keys (deepest last), for teardown.
  final Map<String, List<String>> _hostToJump = {};
  RecordingService? _recording;
  set recordingService(RecordingService? service) => _recording = service;

  /// Shared fallback for interactive connects, test connections and jump hops.
  /// Without an explicit or default verifier, host-key checks fail closed.
  /// Background tools only reuse live authenticated clients.
  Future<bool> Function(String host, int port, String keyType, Uint8List fp,
      {SshConnectionAttempt? attempt})? defaultHostKeyVerifier;

  /// Saved metadata lookup; it never supplies authentication material.
  SshKeyEntry? Function(String keyId)? defaultKeyLookup;

  /// Saved host lookup retained for callers; background auto-connect is disabled.
  Host? Function(String jumpHostId)? defaultJumpHostLookup;

  /// Live agent-forwarding events for the session UI (key icon on the tab,
  /// refusal notification). Host-scoped events (sessionId == null) come from
  /// the per-client handler shared by every shell on that host; ready/refused
  /// are per-shell. Wired in main.dart to
  /// SessionProvider.handleAgentForwardingEvent.
  void Function(String hostId, String? sessionId, AgentForwardingState state)?
      onAgentForwardingEvent;

  /// Prompts the user for a sudo password (elevated SFTP). Set from
  /// main.dart; returning null cancels the elevated SFTP attempt. The
  /// password is used for this attempt only. The legacy `remember` result is
  /// ignored; see [_openElevatedSftp].
  Future<({String password, bool remember})?> Function(Host host)?
      sudoPasswordPrompt;

  /// Writes [text] to the system clipboard for an OSC 52 write request.
  /// Injectable for tests; defaults to the platform clipboard.
  Future<void> Function(String text) clipboardWriter =
      (text) => Clipboard.setData(ClipboardData(text: text));

  SshService(this._storage, {this.hookBus, this.shellIntegration});

  /// Routes a private-OSC event. OSC 52 (when [osc52On]) writes the local
  /// clipboard; everything else falls through to shell integration when
  /// [siOn]. Extracted so the routing is unit-testable without a live session.
  @visibleForTesting
  void dispatchPrivateOsc(
    String code,
    List<String> args, {
    required bool osc52On,
    required bool siOn,
    required String sessionId,
    required int absoluteCursorY,
  }) {
    if (code == '52' && osc52On) {
      final r = Osc52Clipboard.parse(args);
      if (r is Osc52Write) clipboardWriter(r.text);
      return;
    }
    if (siOn) {
      shellIntegration?.handleOsc(sessionId, code, args, absoluteCursorY);
    }
  }

  /// Direct TCP dialer; injectable for tests. Defaults to the native socket.
  @visibleForTesting
  Future<SSHSocket> Function(String host, int port, {Duration? timeout})
      directDialer = SSHSocket.connect;

  /// Proxied dialer; injectable for tests. Defaults to [ConnectionProxy.connect].
  @visibleForTesting
  Future<SSHSocket> Function({
    required ProxySettings settings,
    required String targetHost,
    required int targetPort,
    Duration? timeout,
  }) proxyDialer = ConnectionProxy.connect;

  Future<String?> loadProxyPassword(String hostId) =>
      _storage.loadGenericSecret('proxy_pw_$hostId');

  Future<void> saveProxyPassword(String hostId, String password) =>
      password.isEmpty
          ? _storage.deleteGenericSecret('proxy_pw_$hostId')
          : _storage.saveGenericSecret('proxy_pw_$hostId', password);

  /// Opens the first local-originated TCP transport for [host], routing through
  /// the host's configured proxy when set. Used for a direct connect, the first
  /// bastion hop, and test-connection.
  @visibleForTesting
  Future<SSHSocket> localDial(Host host, {Duration? timeout, SshConnectionAttempt? attempt}) async {
    attempt ??= SshConnectionAttempt();
    attempt.check();
    if (host.proxyType == ProxyType.none) {
      return attempt.wait(directDialer(host.host, host.port, timeout: timeout),
          onLateResult: (socket) => socket.destroy());
    }
    if (host.proxyHost == null ||
        host.proxyHost!.isEmpty ||
        host.proxyPort == null) {
      throw const ProxyException('Proxy enabled but proxy host/port is missing');
    }
    String? pw;
    if (host.proxyUsername?.isNotEmpty == true) {
      if (proxyPasswordPrompt == null) throw const ManualAuthenticationRequired();
      pw = await attempt.wait(proxyPasswordPrompt!(host, attempt));
      attempt.check();
      if (pw == null) throw const AuthenticationCancelled();
    }
    return attempt.wait(proxyDialer(
      settings: ProxySettings(
        type: host.proxyType,
        host: host.proxyHost!,
        port: host.proxyPort!,
        username:
            (host.proxyUsername?.isEmpty ?? true) ? null : host.proxyUsername,
        password: (pw?.isEmpty ?? true) ? null : pw,
      ),
      targetHost: host.host,
      targetPort: host.port,
      timeout: timeout,
    ), onLateResult: (socket) => socket.destroy());
  }

  /// Test-only: register a (fake) client so shell/exec paths can run without
  /// a real network connection.
  @visibleForTesting
  void debugSetClient(String hostId, SSHClient client) {
    _clients[hostId] = client;
  }

  // ── Identity resolution ───────────────────────────────
  //
  // Resolves the SSH key material for a given host, keyed by [host.authType].
  // Centralised so connect / _ensureJumpClient / testConnection don't drift.
  // Only the manually supplied PEM is parsed; no disk/agent/keychain fallback.

  _IdentityResolution _resolveIdentities(Host host, SshCredentials input) =>
      _IdentityResolution(parseManualSshIdentity(host, input));

  // ── Connect ────────────────────────────────────────────

  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
    Future<bool> Function(Host hop, String keyType, Uint8List fp)? verifyHopHostKey,
  }) async {
    final existing = _clients[host.id];
    if (existing != null && !existing.isClosed) return existing;
    final pending = _connecting[host.id];
    if (pending != null) return pending;
    final attempt = _beginAttempt(host.id);
    final future = _connect(host, attempt: attempt, keyEntry: keyEntry, jumpChain: jumpChain,
        verifyHostKey: verifyHostKey, verifyHopHostKey: verifyHopHostKey);
    _connecting[host.id] = future;
    try {
      return await future;
    } finally {
      if (identical(_connecting[host.id], future)) _connecting.remove(host.id);
      _endAttempt(host.id, attempt);
    }
  }

  Future<SSHClient> _connect(
    Host host, {
    required SshConnectionAttempt attempt,
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
    // Verifies each bastion hop's key under its OWN host:port (the target's
    // [verifyHostKey] only covers the destination). Null uses the default verifier.
    Future<bool> Function(Host hop, String keyType, Uint8List fp)?
        verifyHopHostKey,
  }) async {
    if (hookBus != null) {
      final result = hookBus!.fireInterceptable(
        'session.connect.before',
        TransformEvent(sessionId: host.id, data: host.host),
      );
      if (result == null) {
        throw Exception('Connection cancelled by plugin');
      }
    }

    final input = await _requestCredentials(host, attempt);
    final password = input.password;
    final resolution = _resolveIdentities(host, input);
    if (resolution.agentProxy != null) {
      _agentProxies[host.id] = resolution.agentProxy!;
    }

    SSHClient? client;
    SSHSocket? socket;
    try {
      if (jumpChain.isNotEmpty) {
        final lastHop = await dialChain(
            target: host,
            attempt: attempt,
            chain: jumpChain,
            verifyHopHostKey: verifyHopHostKey);
        attempt.check();
        socket = await attempt.wait<SSHSocket>(lastHop.forwardLocal(host.host, host.port),
            onLateResult: (socket) => socket.destroy());
      } else {
        socket = await localDial(host, attempt: attempt);
      }
      attempt.check();
      client = SSHClient(
        socket,
        username: host.username,
        onPasswordRequest: host.authType == AuthType.password ? () => password : null,
        identities: resolution.identities.isNotEmpty ? resolution.identities : null,
        // No system-agent access or automatic key-file fallback.
        agentHandler: null,
        onVerifyHostKey: (type, fp) =>
            _verifyHostKey(host, type.toString(), fp, attempt, verifyHostKey),
        // Built-in keepalive is disabled: HealthMonitorService is the sole
        // pinger (it both keeps the connection alive and measures latency),
        // avoiding a race on the shared global-request reply queue.
        keepAliveInterval: null,
      );
      await attempt.wait(client.authenticated);
      attempt.check();
    } catch (e) {
      final wasCancelled = attempt.isCancelled;
      attempt.cancel();
      client?.close();
      socket?.destroy();
      if (resolution.agentProxy != null) {
        unawaited(_agentProxies[host.id]?.close() ?? Future.value());
        _agentProxies.remove(host.id);
      }
      if (!wasCancelled) _teardownJumpChain(host.id);
      rethrow;
    }
    _clients[host.id] = client;
    return client;
  }

  // ── Jump chain ─────────────────────────────────────────

  /// Resolves [host]'s `jumpHostIds` to a dialable chain. Throws
  /// [JumpChainException] on a hop id that no longer resolves — a config
  /// error callers must surface, not auto-retry. Shared by every entry
  /// point (sessions, test-connection) so resolution stays
  /// consistent.
  static List<JumpHop> resolveJumpChain(
    Host host, {
    required Host? Function(String id) jumpLookup,
    required SshKeyEntry? Function(String keyId) keyLookup,
  }) {
    final chain = <JumpHop>[];
    for (final jid in host.jumpHostIds) {
      final jh = jumpLookup(jid);
      if (jh == null) throw JumpChainException('Jump host not found: $jid');
      final jk = jh.keyId == null ? null : keyLookup(jh.keyId!);
      chain.add((host: jh, keyEntry: jk));
    }
    return chain;
  }

  /// Opens one hop and returns its client + agent proxy (the caller owns
  /// proxy storage/lifetime). [over] null = direct TCP (hop0); otherwise the
  /// socket is the previous client's forwardLocal channel. `@visibleForTesting`
  /// only so tests can stub the socket/auth — production dials through it.
  @visibleForTesting
  Future<({SSHClient client, SystemAgentProxy? proxy})> dialHop(
    Host hop,
    SSHSocket? over, {
    SshKeyEntry? keyEntry,
    SshConnectionAttempt? attempt,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    final scope = attempt ?? SshConnectionAttempt();
    SSHSocket? socket = over;
    SSHClient? client;
    try {
      final input = await _requestCredentials(hop, scope);
      final resolution = _resolveIdentities(hop, input);
      socket ??= await localDial(hop, attempt: scope);
      scope.check();
      client = SSHClient(
        socket,
        username: hop.username,
        onPasswordRequest: hop.authType == AuthType.password ? () => input.password : null,
        identities: resolution.identities.isNotEmpty ? resolution.identities : null,
        onVerifyHostKey: (type, fp) =>
            _verifyHostKey(hop, type.toString(), fp, scope, verifyHostKey),
      );
      await scope.wait(client.authenticated);
      scope.check();
      return (client: client, proxy: resolution.agentProxy);
    } catch (_) {
      scope.cancel();
      client?.close();
      socket?.destroy();
      rethrow;
    }
  }

  /// Shared hop dials have their own lifetime: cancel them only when the last
  /// target releases the prefix, including targets still waiting for auth.
  @visibleForTesting
  Future<SSHClient> dialChain({
    required Host target,
    required List<JumpHop> chain,
    SshConnectionAttempt? attempt,
    Future<bool> Function(Host hop, String keyType, Uint8List fp)? verifyHopHostKey,
  }) async {
    final scope = attempt ?? SshConnectionAttempt();
    scope.check();
    final seen = <String>{};
    for (final hop in chain) {
      if (hop.host.id == target.id || !seen.add(hop.host.id)) {
        throw JumpChainException('Jump chain contains a cycle: ${hop.host.id}');
      }
    }
    final keys = [for (var i = 1; i <= chain.length; i++)
      chain.take(i).map((h) => h.host.id).join('>')];
    _retargetJumpChain(target.id, keys);
    SSHClient? prev;
    try {
      for (var i = 0; i < chain.length; i++) {
        scope.check();
        final cached = _jumpClients[keys[i]];
        if (cached != null && !cached.isClosed) {
          prev = cached;
          continue;
        }
        _jumpClients.remove(keys[i]);
        unawaited(_jumpAgentProxies.remove(keys[i])?.close() ?? Future.value());
        prev = await scope.wait(_ensureHop(keys[i], prev, chain[i], verifyHopHostKey));
      }
      scope.check();
      return prev!;
    } catch (_) {
      if (identical(_hostToJump[target.id], keys)) _teardownJumpChain(target.id);
      rethrow;
    }
  }

  Future<SSHClient> _ensureHop(String prefix, SSHClient? prev, JumpHop hop,
      Future<bool> Function(Host, String, Uint8List)? verifyHopHostKey) async {
    final inflight = _jumpInflight[prefix];
    if (inflight != null) return (await inflight).client;
    final attempt = SshConnectionAttempt();
    _hopAttempts[prefix] = attempt;
    final future = () async {
      final socket = prev == null ? null : await attempt.wait(
          prev.forwardLocal(hop.host.host, hop.host.port),
          onLateResult: (socket) => socket.destroy());
      if (attempt.isCancelled) {
        socket?.destroy();
        attempt.check();
      }
      return attempt.wait(dialHop(hop.host, socket, keyEntry: hop.keyEntry,
        attempt: attempt,
        verifyHostKey: verifyHopHostKey == null ? null
            : (kt, fp) => verifyHopHostKey(hop.host, kt, fp)),
        onLateResult: (r) {
          r.client.close();
          unawaited(r.proxy?.close() ?? Future.value());
        });
    }();
    _jumpInflight[prefix] = future;
    try {
      final r = await future;
      if (attempt.isCancelled) {
        r.client.close();
        unawaited(r.proxy?.close() ?? Future.value());
        attempt.check();
      }
      _jumpClients[prefix] = r.client;
      if (r.proxy != null) _jumpAgentProxies[prefix] = r.proxy!;
      return r.client;
    } finally {
      if (identical(_jumpInflight[prefix], future)) {
        _jumpInflight.remove(prefix);
        _hopAttempts.remove(prefix);
      }
    }
  }

  void _releaseJumpPrefix(String prefix) {
    if (_hostToJump.values.any((keys) => keys.contains(prefix))) return;
    _hopAttempts.remove(prefix)?.cancel();
    _jumpInflight.remove(prefix);
    _jumpClients.remove(prefix)?.close();
    unawaited(_jumpAgentProxies.remove(prefix)?.close() ?? Future.value());
  }

  void _retargetJumpChain(String hostId, List<String> keys) {
    final old = _hostToJump[hostId];
    _hostToJump[hostId] = keys;
    for (final prefix in old?.reversed ?? <String>[]) {
      _releaseJumpPrefix(prefix);
    }
  }

  void _teardownJumpChain(String hostId) {
    final keys = _hostToJump.remove(hostId);
    for (final prefix in keys?.reversed ?? <String>[]) {
      _releaseJumpPrefix(prefix);
    }
  }

  // ── Test connection (TCP + auth, no shell) ────────────

  Future<({bool success, int latencyMs, String? error})> testConnection(
    Host host, {
    String? password,
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
  }) async {
    final stopwatch = Stopwatch()..start();
    final attempt = _beginAttempt(host.id);
    SSHClient? client;
    SSHSocket? socket;
    // Temp (non-cached) hop clients + their agent proxies, all closed in
    // `finally` — a connectivity check must leave no live connections.
    final jumpClients = <SSHClient>[];
    final jumpProxies = <SystemAgentProxy>[];
    SystemAgentProxy? agentProxy;
    try {
      final input = await _requestCredentials(host, attempt, password: password);
      final resolution = _resolveIdentities(host, input);
      if (jumpChain.isNotEmpty) {
        SSHClient? prev;
        for (final hop in jumpChain) {
          final overSocket = prev == null
              ? null
              : await attempt.wait(prev.forwardLocal(hop.host.host, hop.host.port),
                  onLateResult: (socket) => socket.destroy());
          // Shared per-hop dial (same auth/identity path as a real connect);
          // temp clients/proxies are tracked here and closed in `finally`.
          // Manual input can take longer than a network timeout.
          final r = await dialHop(hop.host, overSocket,
                  keyEntry: hop.keyEntry, attempt: attempt);
          jumpClients.add(r.client);
          if (r.proxy != null) jumpProxies.add(r.proxy!);
          prev = r.client;
        }
        attempt.check();
        socket = await attempt.wait<SSHSocket>(prev!.forwardLocal(host.host, host.port),
            onLateResult: (socket) => socket.destroy());
      } else {
        socket = await localDial(host, timeout: const Duration(seconds: 10), attempt: attempt);
      }

      agentProxy = resolution.agentProxy;
      attempt.check();
      final keyReceived = Completer<void>();
      final keyChecked = Completer<void>();
      client = SSHClient(
        socket,
        username: host.username,
        onPasswordRequest: host.authType == AuthType.password ? () => input.password : null,
        identities: resolution.identities.isNotEmpty ? resolution.identities : null,
        onVerifyHostKey: (type, fp) async {
          if (!keyReceived.isCompleted) keyReceived.complete();
          try {
            return await _verifyHostKey(host, type.toString(), fp, attempt, null);
          } finally {
            if (!keyChecked.isCompleted) keyChecked.complete();
          }
        },
      );
      // Network phases time out; the user has the trust dialog's own deadline.
      await attempt.wait(Future.any([client.authenticated, keyReceived.future])
          .timeout(const Duration(seconds: 10)));
      if (keyReceived.isCompleted) await attempt.wait(keyChecked.future);
      await attempt.wait(client.authenticated.timeout(const Duration(seconds: 10)));
      attempt.check();
      stopwatch.stop();
      return (success: true, latencyMs: stopwatch.elapsedMilliseconds, error: null);
    } on SSHAgentUnavailableException catch (e) {
      return (success: false, latencyMs: 0, error: e.message);
    } on TimeoutException {
      return (success: false, latencyMs: 0, error: 'Host unreachable');
    } on SocketException {
      return (success: false, latencyMs: 0, error: 'Host unreachable');
    } catch (e) {
      final msg = e.toString();
      final isAuth = msg.toLowerCase().contains('auth') ||
          msg.toLowerCase().contains('permission denied') ||
          msg.toLowerCase().contains('userauth');
      return (
        success: false,
        latencyMs: 0,
        error: isAuth
            ? 'Authentication failed'
            : (msg.length > 80 ? '${msg.substring(0, 80)}…' : msg),
      );
    } finally {
      attempt.cancel();
      _endAttempt(host.id, attempt);
      client?.close();
      socket?.destroy();
      for (final c in jumpClients) {
        c.close();
      }
      await agentProxy?.close();
      for (final pxy in jumpProxies) {
        await pxy.close();
      }
    }
  }

  // ── Health monitoring ─────────────────────────────────

  /// Host ids with a live client. Used by HealthMonitorService to know which
  /// connections to ping.
  Iterable<String> get connectedHostIds => _clients.keys;

  /// Round-trip latency (ms) of a keepalive ping over [hostId]'s live client,
  /// or null when there is no client or the ping fails / times out. The timeout
  /// is what surfaces half-open connections (the channel has not closed yet).
  Future<int?> measureLatency(String hostId) async {
    final client = _clients[hostId];
    if (client == null) return null;
    final sw = Stopwatch()..start();
    try {
      await client.ping().timeout(const Duration(seconds: 5));
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  // ── Shell session (feeds into xterm Terminal) ──────────

  Future<void> openShell(
    SshSession session, {
    bool useTmux = false,
    String termType = 'xterm-256color',
  }) async {
    final client = _clients[session.host.id];
    if (client == null) throw Exception('Not connected');

    // The tab (and thus TerminalView layout) exists before the handshake
    // finishes, so the terminal already knows its real dimensions — open the
    // PTY at that size instead of a fixed 80x24, which made remote output
    // wrap at half the window width.
    final ptyWidth = session.terminal.viewWidth;
    final ptyHeight = session.terminal.viewHeight;
    final attempt = SshConnectionAttempt();
    _openingShells.remove(session.id)?.attempt.cancel();
    _openingShells[session.id] = (hostId: session.host.id, attempt: attempt);
    final SSHSession shell;
    try {
      shell = await attempt.wait(client.shell(
        pty: SSHPtyConfig(width: ptyWidth, height: ptyHeight, type: termType),
      ), onLateResult: (shell) => shell.close());
      if (attempt.isCancelled) {
        shell.close();
        attempt.check();
      }
      _shells[session.id] = shell;
      _shellToHost[session.id] = session.host.id;
    } finally {
      if (identical(_openingShells[session.id]?.attempt, attempt)) {
        _openingShells.remove(session.id);
      }
    }

    // Legacy host flags never enable or advertise credential forwarding.
    session.agentForwardingState = AgentForwardingState.off;

    // Shell integration (OSC 7/133): route private OSC into the provider before
    // any output arrives, so the first prompt cycle is captured.
    final siOn = shellIntegration != null &&
        session.host.shellIntegration &&
        (isShellIntegrationEnabled?.call() ?? true);
    final osc52On = session.host.osc52Clipboard;
    if (siOn || osc52On) {
      session.terminal.onPrivateOSC = (code, args) => dispatchPrivateOsc(
            code,
            args,
            osc52On: osc52On,
            siOn: siOn,
            sessionId: session.id,
            absoluteCursorY: session.terminal.buffer.absoluteCursorY,
          );
    }

    // Session-template setup (cd/export, and the snippet's DONE trigger)
    // rides the same invisible handshake as shell integration — one
    // bootstrap, one payload, one DONE sentinel. See
    // docs/superpowers/specs/2026-06-06-session-template-design.md.
    final injectOn =
        shellIntegration != null && (siOn || session.host.hasTemplateSetup);

    var snippetSent = false;
    void maybeSendStartupSnippet() {
      if (snippetSent) return;
      snippetSent = true;
      final snippet = session.host.startupSnippet;
      // tmux `new -A` re-attach would replay the snippet into a live
      // session — cd/export are idempotent, the snippet is not. Skip it.
      if (snippet == null || snippet.trim().isEmpty || useTmux) return;
      shell.write(Uint8List.fromList(const Utf8Encoder()
          .convert(snippet.endsWith('\n') ? snippet : '$snippet\n')));
    }

    hookBus?.fireObserve('session.connect', ObserveEvent(
      sessionId: session.id,
      payload: {
        'host': session.host.host,
        'username': session.host.username,
        'port': session.host.port,
      },
    ));

    if (useTmux) {
      shell.write(Uint8List.fromList('tmux new-session -A -s yourssh\n'.codeUnits));
    }

    final initialCommand = session.initialCommand;
    if (initialCommand != null && initialCommand.isNotEmpty) {
      shell.write(Uint8List.fromList(const Utf8Encoder().convert('$initialCommand\n')));
    }

    // Invisible shell-integration injection (two-phase handshake; see
    // docs/superpowers/specs/2026-06-03-invisible-shell-integration-design.md).
    // Readiness → bootstrap → RDY → payload (never echoed via read -rs) →
    // DONE → discard the withheld bootstrap echo. Readiness is the bracketed-
    // paste toggle (line editor reading) + a settle period. This is passive:
    // never send Enter to discover whether a shell is ready. Without a signal,
    // skip injection entirely to avoid writing into an unready session.
    InjectionGate? gate;
    final readiness = InjectionReadiness();
    Timer? settleTimer;
    Timer? doneTimer;
    var injectionAborted = false;

    void cancelReadinessTimers() {
      settleTimer?.cancel();
    }

    void launchInjection() {
      if (!injectOn ||
          gate != null ||
          injectionAborted ||
          !readiness.bpOn ||
          !identical(_shells[session.id], shell)) {
        return;
      }
      cancelReadinessTimers();
      final bootstrap = shellIntegration!.buildBootstrapLine();
      gate = InjectionGate(
        readySentinel: ShellIntegrationService.kReadySentinel,
        doneSentinel: ShellIntegrationService.kDoneSentinel,
        // Generous: the head is echo + line-editor redraw noise; only a
        // genuinely streaming command produces more, and that must be shown.
        maxHold: 16384,
      );
      shell.write(Uint8List.fromList(bootstrap.codeUnits));
      doneTimer = Timer(const Duration(seconds: 2), () {
        final g = gate;
        if (g == null || !g.isHolding) return;
        final out = g.flush(); // degrade: show as-is
        if (out.isNotEmpty) session.terminal.write(out);
      });
    }

    final done = Completer<void>();
    const utf8 = Utf8Decoder(allowMalformed: true);

    // Pipe SSH output → xterm terminal; complete when shell closes
    final sessionLabel =
        '${session.host.label} (${session.host.username}@${session.host.host})';
    shell.stdout.cast<List<int>>().listen(
      (data) {
        var text = utf8.convert(data);
        if (hookBus != null) {
          text = hookBus!.fireTransform(
              'terminal.output', TransformEvent(sessionId: session.id, data: text));
        }

        if (injectOn && gate == null && !injectionAborted) {
          final sig = readiness.onChunk(text);
          if (sig == ReadinessSignal.altScreen) {
            injectionAborted = true; // vim/less owns the tty — never inject
            cancelReadinessTimers();
          } else if (readiness.bpOn) {
            // Line editor is reading: inject once the redraw burst settles.
            settleTimer?.cancel();
            settleTimer =
                Timer(const Duration(milliseconds: 250), launchInjection);
          } else {
            settleTimer?.cancel();
          }
        }

        final g = gate;
        if (g != null) {
          final wasHolding = g.isHolding;
          final r = g.feed(text);
          if (r.sendPayload) {
            // Utf8Encoder (not codeUnits): workingDir/env values may be
            // non-ASCII. The local `utf8` decoder shadows dart:convert's.
            shell.write(Uint8List.fromList(const Utf8Encoder().convert(
                shellIntegration!.buildPayloadLine(
              includeInstaller: siOn,
              workingDir: session.host.workingDir,
              envVars: session.host.envVars,
            ))));
          }
          if (r.emit == null) return; // withheld until DONE / timeout
          if (wasHolding && !g.isHolding) {
            doneTimer?.cancel();
            // DONE seen: handshake completed cleanly — type the startup
            // snippet exactly as if the user had, visible and recorded.
            // The doneTimer flush path (degraded handshake) never lands
            // here, so an unconfirmed handshake never types the snippet.
            maybeSendStartupSnippet();
          }
          text = r.emit!;
          if (r.redrawPrompt) {
            // Only the prompt present before the hidden command was shown.
            // Reset that logical line, including its actual soft-wrapped rows;
            // never estimate rows from the bootstrap's echoed byte length.
            // Use terminal escapes so recordings replay the same replacement.
            final buffer = session.terminal.buffer;
            var row = buffer.absoluteCursorY;
            var visibleRow = buffer.cursorY;
            var reset = '\r\x1b[2K';
            while (visibleRow > 0 && buffer.lines[row].isWrapped) {
              reset += '\x1b[1A\x1b[2K';
              row--;
              visibleRow--;
            }
            text = reset + text;
          }
          if (text.isEmpty) return; // echo head discarded, nothing to show
        }
        session.terminal.write(text);
        _recording?.writeOutput(session.id, text);
        try {
          NotificationService.instance.onTerminalData(
            text,
            sessionId: session.id,
            sessionLabel: sessionLabel,
          );
        } catch (e) {
          // Notifications must never break TTY output — log and move on.
          debugPrint('[SshService] notification handler threw: $e');
        }
      },
      onDone: () {
        cancelReadinessTimers();
        doneTimer?.cancel();
        final g = gate;
        if (g != null && g.isHolding) {
          final out = g.flush();
          if (out.isNotEmpty) session.terminal.write(out);
        }
        _onShellClosed(session);
        if (!done.isCompleted) done.complete();
      },
      onError: (Object e) {
        injectionAborted = true;
        cancelReadinessTimers();
        doneTimer?.cancel();
        if (!done.isCompleted) done.completeError(e);
      },
      cancelOnError: true,
    );
    shell.stderr.cast<List<int>>().listen(
      (data) => session.terminal.write(utf8.convert(data)),
    );

    // Pipe xterm input → SSH shell
    session.terminal.onOutput = (data) {
      // A user keystroke before the handshake starts cancels the injection:
      // the bootstrap must never be appended to whatever they are typing.
      if (injectOn && gate == null && !injectionAborted) {
        injectionAborted = true;
        cancelReadinessTimers();
      }
      if (hookBus != null) {
        final result = hookBus!.fireInterceptable(
            'terminal.input', TransformEvent(sessionId: session.id, data: data));
        if (result == null) return; // cancelled by plugin
        // Utf8Encoder (not codeUnits): non-ASCII input (e.g. Vietnamese) has
        // code units > 0xFF that Uint8List.fromList truncates, corrupting the
        // bytes the server receives. The local `utf8` decoder shadows
        // dart:convert's, so use Utf8Encoder explicitly.
        shell.write(Uint8List.fromList(const Utf8Encoder().convert(result)));
      } else {
        shell.write(Uint8List.fromList(const Utf8Encoder().convert(data)));
      }
    };

    // Handle terminal resize
    session.terminal.onResize = (w, h, pw, ph) {
      shell.resizeTerminal(w, h);
    };
    // The view may have resized while the shell channel was opening (onResize
    // was still null then, so that event was lost) — sync once so the remote
    // never keeps a stale size.
    if (session.terminal.viewWidth != ptyWidth ||
        session.terminal.viewHeight != ptyHeight) {
      shell.resizeTerminal(
          session.terminal.viewWidth, session.terminal.viewHeight);
    }

    // Wait until the remote shell actually closes
    await done.future;
  }

  void _onShellClosed(SshSession session) {
    hookBus?.fireObserve('session.disconnect',
        ObserveEvent(sessionId: session.id, payload: {}));
    _shells.remove(session.id);
    _shellToHost.remove(session.id);
    session.terminal.write('\r\n\x1b[31m[Connection closed]\x1b[0m\r\n');
    // Drop the closures that pin the closed shell — otherwise it lingers in
    // memory until the widget tree releases the terminal.
    session.terminal.onOutput = null;
    session.terminal.onResize = null;
    session.terminal.onPrivateOSC = null;
    shellIntegration?.clear(session.id);
    NotificationService.instance.removeSession(session.id);
    _recording?.onShellClosed(session.id);
  }

  /// Opens a forwarded TCP socket to [targetHost]:[targetPort] through the SSH
  /// host identified by [jumpHostId]. Reuses `_ensureClient` (which resolves
  /// the full jump chain for the bastion), then calls `forwardLocal`.
  /// [forHostId] is the consuming host id used for teardown bookkeeping.
  Future<SSHSocket> openTunnelSocket(
      String jumpHostId, String targetHost, int targetPort, String forHostId) async {
    final jumpHost = defaultJumpHostLookup?.call(jumpHostId);
    if (jumpHost == null) throw StateError('Jump host $jumpHostId not found');
    final client = await _ensureClient(jumpHost);
    // Register the consuming host so teardown walks the chain correctly.
    _retargetJumpChain(forHostId, [jumpHostId]);
    return client.forwardLocal(targetHost, targetPort);
  }

  /// Legacy protocol helper: reads only values entered in this app run.
  /// SSH authentication never calls this method.
  Future<String?> loadPassword(String hostId) => _storage.loadPassword(hostId);

  /// Returns a live client only. The user must manually authenticate first.
  Future<SSHClient> ensureClient(Host host) => _ensureClient(host);

  Future<SSHClient> _ensureClient(Host host) async {
    final existing = _clients[host.id];
    if (existing != null && !existing.isClosed) return existing;
    if (existing != null) _clients.remove(host.id); // dropped link — evict
    throw StateError('Connect manually before using files, monitoring, or tools.');
  }

  // ── Exec ───────────────────────────────────────────────

  /// [auditSource] tags the audit event ('app', 'bulk', 'devops',
  /// 'plugin:…'); pass null for internal polling probes that would flood
  /// the log (network stats).
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command, {
    String? auditSource = 'app',
  }) async {
    var cmd = command;

    if (hookBus != null) {
      final transformed = hookBus!.fireInterceptable(
        'command.before',
        TransformEvent(sessionId: host.id, data: cmd),
      );
      if (transformed == null) {
        return (stdout: '', stderr: 'Command cancelled by plugin', exitCode: -1);
      }
      cmd = transformed;
    }

    final originalCommand = cmd;
    final SSHClient client;
    final SSHRunResult result;
    try {
      client = await _ensureClient(host);
      result = await client.runWithResult(cmd);
    } catch (e) {
      if (auditSource != null) {
        audit?.record(AuditEvent.now(
          type: AuditEventType.exec,
          host: host,
          command: originalCommand,
          meta: {'source': auditSource, 'error': '$e'},
        ));
      }
      rethrow;
    }
    final execResult = (
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
      exitCode: result.exitCode ?? -1,
    );

    if (auditSource != null) {
      audit?.record(AuditEvent.now(
        type: AuditEventType.exec,
        host: host,
        command: originalCommand,
        exitCode: execResult.exitCode,
        meta: {'source': auditSource},
      ));
    }

    hookBus?.fireObserve(
      'command.after',
      ObserveEvent(
        sessionId: host.id,
        payload: {
          'command': originalCommand,
          'stdout': execResult.stdout,
          'stderr': execResult.stderr,
          'exitCode': execResult.exitCode,
        },
      ),
    );

    return execResult;
  }

  /// Read-only monitoring probes reuse a live connection; never auto-connect
  /// or run command-transform plugins for a background poll.
  Future<({String stdout, String stderr, int exitCode})> execForMonitoring(
    Host host, String command,
  ) async {
    final client = _clients[host.id];
    if (client == null || client.isClosed) throw StateError('SSH host is disconnected');
    final result = await boundedSshExec(client, command,
      timeout: const Duration(seconds: 8), maxBytes: 512 * 1024);
    return (stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
      exitCode: result.exitCode ?? -1);
  }

  /// MCP uses only an existing authenticated connection and bounded output.
  Future<({String stdout, String stderr, int exitCode})> execForMcp(Host host, String command) async {
    final client = _clients[host.id];
    if (client == null || client.isClosed) throw StateError('SSH host is disconnected');
    try {
      final result = await boundedSshExec(client, command);
      audit?.record(AuditEvent.now(type: AuditEventType.exec, host: host, command: command,
        exitCode: result.exitCode, meta: {'source': 'mcp'}));
      return (stdout: utf8.decode(result.stdout, allowMalformed: true),
        stderr: utf8.decode(result.stderr, allowMalformed: true), exitCode: result.exitCode ?? -1);
    } catch (e) {
      audit?.record(AuditEvent.now(type: AuditEventType.exec, host: host, command: command,
        meta: {'source': 'mcp', 'error': '$e'}));
      rethrow;
    }
  }

  /// Opens a persistent SSH exec channel and yields stdout lines.
  /// Cancelling the returned stream's subscription closes the channel —
  /// the remote process receives SIGHUP.
  Stream<String> execStream(
    Host host,
    String command, {
    String? auditSource,
  }) {
    final controller = StreamController<String>();
    _ensureClient(host).then((client) async {
      final SSHSession session;
      try {
        session = await client.execute(command);
      } catch (e) {
        controller.addError(e);
        unawaited(controller.close());
        return;
      }
      if (auditSource != null) {
        audit?.record(AuditEvent.now(
          type: AuditEventType.exec,
          host: host,
          command: command,
          meta: {'source': auditSource},
        ));
      }
      final sub = session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            controller.add,
            onError: controller.addError,
            onDone: () {
              session.close();
              if (!controller.isClosed) unawaited(controller.close());
            },
            cancelOnError: false,
          );
      controller.onCancel = () async {
        await sub.cancel();
        session.close();
      };
    }).catchError((Object e, StackTrace st) {
      controller.addError(e, st);
    });
    return controller.stream;
  }

  // ── SFTP ───────────────────────────────────────────────

  Future<SftpClient> openSftp(Host host, {bool interactive = true}) async {
    final client = await _ensureClient(host);
    if (host.sftpMode == SftpMode.normal) return client.sftp();
    return _openElevatedSftp(client, host, interactive: interactive);
  }

  /// Elevated SFTP (sudo / custom command). Probe and validation execs talk
  /// to the SSHClient directly — they intentionally bypass the plugin
  /// HookBus, and the sudo password only ever travels via stdin.
  Future<SftpClient> _openElevatedSftp(
    SSHClient client,
    Host host, {
    required bool interactive,
  }) async {
    // Password input is per attempt and is never persisted.
    final probeCommand = buildPathProbeCommand();
    final orchestrator = SudoSftpOrchestrator<SftpClient>(
      runExec: (cmd) async {
        // The sftp-server path is static for a host; cache the probe result so
        // every file op / transfer doesn't pay an extra round-trip for it.
        if (cmd == probeCommand) {
          final cached = _sudoServerPath[host.id];
          if (cached != null) {
            return (stdout: cached, stderr: '', exitCode: 0);
          }
        }
        try {
          final r = await client
              .runWithResult(cmd)
              .timeout(const Duration(seconds: 15));
          final out = utf8.decode(r.stdout, allowMalformed: true);
          final result = (
            stdout: out,
            stderr: utf8.decode(r.stderr, allowMalformed: true),
            exitCode: r.exitCode ?? -1,
          );
          if (cmd == probeCommand && result.exitCode == 0) {
            final p = out.trim();
            if (p.isNotEmpty) _sudoServerPath[host.id] = p;
          }
          return result;
        } on TimeoutException {
          throw SudoSftpException(SudoSftpFailureReason.handshakeFailed,
              detail: 'Timed out running: $cmd');
        }
      },
      runExecWithStdin: (cmd, stdinData) async {
        final session = await client.execute(cmd);
        final stderrBuf = StringBuffer();
        final stdoutDone = Completer<void>();
        final stderrDone = Completer<void>();
        session.stdout.listen((_) {},
            onDone: stdoutDone.complete,
            onError: (_) => stdoutDone.complete());
        session.stderr.cast<List<int>>().listen(
            (d) => stderrBuf.write(utf8.decode(d, allowMalformed: true)),
            onDone: stderrDone.complete,
            onError: (_) => stderrDone.complete());
        session.stdin.add(Uint8List.fromList(stdinData));
        await session.stdin.close(); // EOF: a wrong password fails fast
        try {
          await Future.wait(
                  [stdoutDone.future, stderrDone.future, session.done])
              .timeout(const Duration(seconds: 15));
        } on TimeoutException {
          session.close();
          throw SudoSftpException(SudoSftpFailureReason.handshakeFailed,
              detail:
                  'sudo validation timed out (check requiretty / PAM): $cmd');
        }
        return (stderr: stderrBuf.toString(), exitCode: session.exitCode ?? -1);
      },
      openSftpExec: (cmd, {stdinPreamble}) async {
        final sftp = await client.sftpOnExec(cmd, stdinPreamble: stdinPreamble);
        try {
          await sftp.handshake.timeout(const Duration(seconds: 15));
        } catch (_) {
          sftp.close();
          rethrow;
        }
        return sftp;
      },
    );
    final sftp = await orchestrator.openForHost(
      host,
      interactive: interactive,
      getPassword: ({required bool interactive, required int attempt}) async {
        final r = await _sudoPasswordFor(host,
            interactive: interactive, attempt: attempt);
        if (r == null) return null;
        return r.password;
      },
    );
    return sftp;
  }

  /// Elevated SFTP only accepts an explicit interactive response.
  Future<({String password, bool persist})?> _sudoPasswordFor(
    Host host, {
    required bool interactive,
    required int attempt,
  }) async {
    if (!interactive) return null;
    final prompted = await sudoPasswordPrompt?.call(host);
    if (prompted == null) return null;
    return (password: prompted.password, persist: false);
  }

  // Cached SFTP client per host, reused for path autocomplete listings.
  final Map<String, SftpClient> _completionSftp = {};

  // Cached sftp-server path per host (elevated SFTP), so each operation skips
  // re-probing. Cleared on disconnect.
  final Map<String, String> _sudoServerPath = {};

  /// List a remote directory for path autocomplete. Reuses a cached SFTP
  /// client per host. Returns entry names (directories carry a trailing '/').
  /// Never throws — returns an empty list on any failure and drops the cached
  /// client so a later call can reopen it (self-heals after reconnect).
  Future<List<String>> listDirectory(Host host, String path) async {
    try {
      final sftp =
          _completionSftp[host.id] ??= await openSftp(host, interactive: false);
      final items = await sftp.listdir(path.isEmpty ? '.' : path);
      return items
          .map((e) => e.filename + (e.attr.isDirectory ? '/' : ''))
          .where((n) => n != './' && n != '../')
          .toList();
    } catch (e) {
      _completionSftp.remove(host.id);
      debugPrint('[SshService] listDirectory failed for $path: $e');
      return const [];
    }
  }

  // ── Send input to shell ────────────────────────────────

  /// Sends [text] directly to the shell of [sessionId].
  ///
  /// Returns false when the session has no live shell (e.g. it closed
  /// mid-disconnect) so callers don't show success feedback for input that
  /// never reached the server.
  bool sendInput(String sessionId, String text) {
    final shell = _shells[sessionId];
    if (shell == null) return false;
    // Utf8Encoder (not codeUnits): snippet/insert text may be non-ASCII.
    shell.write(Uint8List.fromList(const Utf8Encoder().convert(text)));
    return true;
  }

  // ── Disconnect ─────────────────────────────────────────

  void disconnect(String hostId) {
    _connecting.remove(hostId);
    for (final attempt in _attempts.remove(hostId) ?? <SshConnectionAttempt>{}) {
      attempt.cancel();
    }
    final openingIds = _openingShells.entries
        .where((e) => e.value.hostId == hostId).map((e) => e.key).toList();
    for (final id in openingIds) {
      _openingShells.remove(id)?.attempt.cancel();
    }
    final sessionIds = _shellToHost.entries
        .where((e) => e.value == hostId)
        .map((e) => e.key)
        .toList();
    for (final id in sessionIds) {
      _shells.remove(id);
      _shellToHost.remove(id);
      NotificationService.instance.removeSession(id);
      shellIntegration?.clear(id);
    }
    _clients[hostId]?.close();
    _clients.remove(hostId);
    // The SFTP completion client rides the SSHClient just closed; drop it so a
    // reconnect opens a fresh one instead of reusing the dead channel.
    _completionSftp.remove(hostId);
    _sudoServerPath.remove(hostId);
    unawaited(_agentProxies[hostId]?.close() ?? Future.value());
    _agentProxies.remove(hostId);

    _teardownJumpChain(hostId);
  }

  void disconnectSession(String sessionId) {
    _openingShells.remove(sessionId)?.attempt.cancel();
    _shells[sessionId]?.close();
    _shells.remove(sessionId);
    _shellToHost.remove(sessionId);
    NotificationService.instance.removeSession(sessionId);
    shellIntegration?.clear(sessionId);
  }

  bool isConnected(String hostId) => _clients[hostId]?.isClosed == false;

  // ── OS Detection ────────────────────────────────────────

  static String? parseOsFromUname(String output) {
    final s = output.trim();
    if (s.contains('Linux')) return 'linux';
    if (s.contains('Darwin')) return 'macos';
    if (s.contains('Windows') || s.contains('MINGW') || s.contains('CYGWIN')) return 'windows';
    return null;
  }

  Future<String?> detectOs(Host host) async {
    try {
      // auditSource: null — internal OS probe on (almost) every connect;
      // auditing it would pollute the trail with rows the user never ran.
      final result =
          await exec(host, 'uname -s 2>/dev/null || ver', auditSource: null);
      final os = parseOsFromUname(result.stdout);
      if (os != 'linux') return os;
      // Linux: best-effort distro probe — generic 'linux' on any failure.
      try {
        final release = await exec(host, 'cat /etc/os-release 2>/dev/null',
            auditSource: null);
        final id = parseOsReleaseId(release.stdout);
        if (id != null) return normalizeDistroId(id);
      } catch (_) {}
      return 'linux';
    } catch (e) {
      debugPrint('[SshService] OS detect failed for ${host.host}: $e');
      return null;
    }
  }
}

/// Return value of [_SshService._resolveIdentities]. The optional [agentProxy]
/// must stay open until SSH authentication completes — agent-backed identities
/// need the socket to sign challenges.
class _IdentityResolution {
  final List<SSHKeyPair> identities;
  final SystemAgentProxy? agentProxy;

  const _IdentityResolution(this.identities) : agentProxy = null;
}

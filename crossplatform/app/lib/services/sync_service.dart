import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/host.dart';
import 'workspace_sync.dart';
import '../providers/sync_provider.dart';
import '../services/supabase_service.dart';
import '../services/sync_encryption.dart';

class SyncPayload {
  final List<Host> hosts;
  final Map<String, String> passwords;
  final DateTime updatedAt;
  final Map<String, dynamic> workspace;
  SyncPayload({
    required this.hosts,
    required this.passwords,
    required this.updatedAt,
    this.workspace = const {},
  });
}

class SyncService {
  static const _lastPushKey = 'sync_last_push_at';
  static const _pendingPushKey = 'sync_pending_push';
  static const _revisionKey = 'sync_local_revision';

  final SyncProvider _syncProvider;
  SupabaseService? _cachedSupabase;
  Timer? _retryTimer;
  Future<List<Host>> Function()? _getHosts;
  Future<Map<String, String>> Function()? _loadPasswords;
  bool _syncing = false;

  SyncService(this._syncProvider);

  /// Overrides the cached [SupabaseService] instance. Intended for tests only.
  @visibleForTesting
  set cachedSupabase(SupabaseService value) => _cachedSupabase = value;

  SupabaseService? _getSupabase() {
    if (!_syncProvider.isSupabaseConfigured || !_syncProvider.hasSyncCode) {
      return null;
    }
    final url = _syncProvider.supabaseUrl;
    final key = _syncProvider.supabaseAnonKey;
    final code = _syncProvider.syncCode;
    if (_cachedSupabase == null ||
        _cachedSupabase!.url != url ||
        _cachedSupabase!.anonKey != key ||
        _cachedSupabase!.syncCode != code) {
      _cachedSupabase = SupabaseService(url, key, code);
    }
    return _cachedSupabase;
  }

  // ── Static helpers (testable without instance) ────────────

  static String buildPayload({
    required List<Host> hosts,
    required Map<String, String> passwords,
    Map<String, dynamic> workspace = const {},
  }) {
    return jsonEncode({
      'hosts': hosts.map((h) {
        final json = h.toJson();
        json.remove('detectedOs');
        return json;
      }).toList(),
      'passwords': passwords,
      'workspace': workspace,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static SyncPayload parsePayload(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final hosts = (map['hosts'] as List)
        .map((e) => Host.fromJson(e as Map<String, dynamic>))
        .toList();
    final passwords = (map['passwords'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as String),
    );
    return SyncPayload(
      hosts: hosts,
      passwords: passwords,
      workspace: Map<String, dynamic>.from(map['workspace'] as Map? ?? {}),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  static bool shouldPullRemote(DateTime remoteUpdatedAt, DateTime? lastPushAt) {
    if (lastPushAt == null) return true; // new device: always pull remote
    return remoteUpdatedAt.isAfter(lastPushAt);
  }

  // ── Push ──────────────────────────────────────────────────

  Future<void> push({
    required List<Host> hosts,
    required Future<Map<String, String>> Function() loadPasswords,
  }) async {
    if (!_syncProvider.isSupabaseConfigured) return;
    if (!_syncProvider.hasSyncCode) {
      _syncProvider.setError(
        'Generate or enter a sync code in Settings → Sync.',
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final revision = const Uuid().v4();
    await prefs.setString(_revisionKey, revision);
    await prefs.setBool(_pendingPushKey, true);
    if (_syncing) return;
    final supabase = _getSupabase();
    if (supabase == null) {
      _syncProvider.setError(
        'Supabase not configured. Enter your project URL and anon key in Settings → Sync.',
      );
      return;
    }
    _syncing = true;
    try {
      _syncProvider.setStatus(SyncStatus.syncing);
      final passwords = await loadPasswords();
      final payload = buildPayload(
        hosts: hosts,
        passwords: passwords,
        workspace: await WorkspaceSync.snapshot(),
      );
      final encrypted = await SyncEncryption.encrypt(
        payload,
        _syncProvider.syncCode,
      );
      await supabase.upsertPayload(encrypted);
      await prefs.setString(
        _lastPushKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      // Never mark edits made during encryption / network IO as uploaded.
      if (prefs.getString(_revisionKey) == revision) {
        await prefs.setBool(_pendingPushKey, false);
      }
      _syncProvider.setStatus(SyncStatus.synced);
    } catch (e) {
      await prefs.setBool(_pendingPushKey, true);
      _syncProvider.setError(e.toString());
    } finally {
      _syncing = false;
    }
  }

  // ── Pull ──────────────────────────────────────────────────

  Future<SyncPayload?> pull() async {
    if (!_syncProvider.enabled) return null;
    if (_syncing) return null;
    final supabase = _getSupabase();
    if (supabase == null) {
      _syncProvider.setError(
        'Supabase not configured. Enter your project URL and anon key in Settings → Sync.',
      );
      return null;
    }
    _syncing = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      _syncProvider.setStatus(SyncStatus.syncing);
      if (prefs.getBool(_pendingPushKey) ?? false) {
        _syncProvider.setError('本机修改尚未同步，请先完成上传再拉取远端数据。');
        return null;
      }
      final lastPushStr = prefs.getString(_lastPushKey);
      final lastPushAt = lastPushStr != null
          ? DateTime.parse(lastPushStr)
          : null;
      final remoteUpdatedAt = await supabase.fetchUpdatedAt();
      if (remoteUpdatedAt == null) {
        _syncProvider.setStatus(SyncStatus.synced);
        return null;
      }
      if (!shouldPullRemote(remoteUpdatedAt, lastPushAt)) {
        _syncProvider.setStatus(SyncStatus.synced);
        return null;
      }
      final encrypted = await supabase.fetchPayload();
      if (encrypted == null) {
        _syncProvider.setStatus(SyncStatus.synced);
        return null;
      }
      final decrypted = await SyncEncryption.decrypt(
        encrypted,
        _syncProvider.syncCode,
      );
      final result = parsePayload(decrypted);
      if (prefs.getBool(_pendingPushKey) ?? false) {
        throw StateError('拉取期间本机有新修改，请先上传。');
      }
      await WorkspaceSync.restore(result.workspace);
      await prefs.setBool(_pendingPushKey, false);
      _syncProvider.setStatus(SyncStatus.synced);
      return result;
    } catch (e) {
      _syncProvider.setError(e.toString());
      return null;
    } finally {
      _syncing = false;
    }
  }

  // ── Retry timer ───────────────────────────────────────────

  void startRetryTimer({
    required Future<List<Host>> Function() getHosts,
    required Future<Map<String, String>> Function() loadPasswords,
  }) {
    _getHosts = getHosts;
    _loadPasswords = loadPasswords;
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool(_pendingPushKey) ?? false;
      if (pending && _getHosts != null && _loadPasswords != null) {
        final hosts = await _getHosts!();
        await push(hosts: hosts, loadPasswords: _loadPasswords!);
      }
    });
  }

  void restartRetryTimer() {
    if (_getHosts != null && _loadPasswords != null) {
      startRetryTimer(getHosts: _getHosts!, loadPasswords: _loadPasswords!);
    }
  }

  void stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // ── Disable ───────────────────────────────────────────────

  /// Stops the retry timer, deletes the remote row (best-effort) and clears
  /// local Supabase config. Returns null on success, or an error message if
  /// the remote delete failed — caller should surface that so the user knows
  /// the cloud row may still exist.
  Future<String?> disableAndDelete() async {
    stopRetryTimer();
    String? remoteError;
    try {
      final supabase = _getSupabase();
      if (supabase != null) {
        await supabase.deleteRow();
      }
    } catch (e) {
      remoteError = e.toString();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingPushKey);
    await prefs.remove(_lastPushKey);
    await _syncProvider.clearSupabaseConfig();
    return remoteError;
  }

  void dispose() {
    stopRetryTimer();
  }
}

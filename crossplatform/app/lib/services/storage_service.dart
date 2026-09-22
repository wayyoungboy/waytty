import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host.dart';
import '../models/known_host.dart';
import 'local_ssh_key_store.dart';

class StorageService {
  final privateKeys = LocalSshKeyStore();
  static const _hostsKey = 'yourssh.hosts';

  // Only values explicitly entered during this app run are held here.
  // Never load, migrate, enumerate, or delete the user's OS keychain items.
  final Map<String, String> _sessionSecrets = {};

  void clearSessionSecrets() {
    _sessionSecrets.clear();
    privateKeys.lock();
  }

  // ── Hosts ──────────────────────────────────────────────

  Future<List<Host>> loadHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hostsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Host.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveHosts(List<Host> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostsKey, jsonEncode(hosts.map((h) => h.toJson()).toList()));
  }

  // ── In-memory values supplied by the user ──────────────────
  Future<void> _saveSecret(String key, String value) async {
    _sessionSecrets[key] = value;
  }

  Future<String?> _loadSecret(String key) async => _sessionSecrets[key];

  Future<void> _deleteSecret(String key) async {
    _sessionSecrets.remove(key);
  }

  Future<void> savePassword(String hostId, String password) =>
      _saveSecret('pw_$hostId', password);

  Future<String?> loadPassword(String hostId) => _loadSecret('pw_$hostId');

  Future<void> deletePassword(String hostId) => _deleteSecret('pw_$hostId');

  /// Sudo password explicitly entered in this app run; never persisted.
  Future<void> saveSudoPassword(String hostId, String password) =>
      _saveSecret('sudopw_$hostId', password);

  Future<String?> loadSudoPassword(String hostId) =>
      _loadSecret('sudopw_$hostId');

  Future<void> deleteSudoPassword(String hostId) =>
      _deleteSecret('sudopw_$hostId');

  Future<void> savePassphrase(String keyId, String passphrase) =>
      _saveSecret('pp_$keyId', passphrase);

  Future<String?> loadPassphrase(String keyId) => _loadSecret('pp_$keyId');

  /// Generic secret store for app-scoped secrets (e.g., sync passphrase).
  /// Caller is responsible for key namespacing.
  Future<void> saveGenericSecret(String key, String value) =>
      _saveSecret(key, value);

  Future<String?> loadGenericSecret(String key) => _loadSecret(key);

  Future<void> deleteGenericSecret(String key) => _deleteSecret(key);

  // ── Known Hosts ────────────────────────────────────────────

  static const _knownHostsKey = 'yourssh.known_hosts';

  Future<List<KnownHost>> loadKnownHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_knownHostsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => KnownHost.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveKnownHosts(List<KnownHost> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _knownHostsKey, jsonEncode(hosts.map((h) => h.toJson()).toList()));
  }

  // ── Pinned Groups ──────────────────────────────────────────

  static const _pinnedGroupsKey = 'yourssh.pinned_groups';

  Future<List<String>> loadPinnedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_pinnedGroupsKey) ?? [];
  }

  Future<void> savePinnedGroups(List<String> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedGroupsKey, groups);
  }
}

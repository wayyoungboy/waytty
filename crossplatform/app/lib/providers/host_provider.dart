import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/host.dart';
import '../services/storage_service.dart';

class HostProvider extends ChangeNotifier {
  final StorageService _storage;
  List<Host> _hosts = [];
  List<String> _pinnedGroups = [];
  String _search = '';
  late final Future<void> ready;
  String? loadError;

  /// Called after any mutation so SyncService can push.
  Future<void> Function()? onMutation;

  /// Fired before a host is removed so dependents (tunnels) can shut down.
  void Function(String hostId)? onHostDeleted;

  HostProvider(this._storage) {
    ready = _load();
  }

  List<Host> get hosts {
    if (_search.isEmpty) return List.unmodifiable(_hosts);
    final q = _search.toLowerCase();
    return List.unmodifiable(
      _hosts.where(
        (h) =>
            h.label.toLowerCase().contains(q) ||
            h.host.toLowerCase().contains(q),
      ),
    );
  }

  List<Host> get allHosts => List.unmodifiable(_hosts);

  /// Lookup by id without allocating a list copy — the common "fresh host"
  /// pattern (session snapshots go stale after copyWith).
  Host? byId(String id) {
    for (final h in _hosts) {
      if (h.id == id) return h;
    }
    return null;
  }

  List<String> get pinnedGroups => List.unmodifiable(_pinnedGroups);

  Future<void> addGroup(String name) async {
    await _readyForWrite();
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final alreadyExists = _pinnedGroups.any(
      (g) => g.toLowerCase() == trimmed.toLowerCase(),
    );
    if (alreadyExists) return;
    _pinnedGroups.add(trimmed);
    await _storage.savePinnedGroups(_pinnedGroups);
    notifyListeners();
    await onMutation?.call();
  }

  Future<void> removeGroup(String name) async {
    await _readyForWrite();
    _pinnedGroups.removeWhere((g) => g.toLowerCase() == name.toLowerCase());
    await _storage.savePinnedGroups(_pinnedGroups);
    notifyListeners();
    await onMutation?.call();
  }

  /// Rename a complete subtree. Segment boundaries keep "prod2" separate.
  Future<void> renameGroup(String source, String destination) async {
    await _readyForWrite();
    final target = destination.trim();
    if (source == target) return;
    if (target.isEmpty ||
        target
            .split('/')
            .any((s) => s.trim().isEmpty || s == '.' || s == '..')) {
      throw ArgumentError('分组名称不能为空，层级之间使用 /');
    }
    if (target.startsWith('$source/')) throw ArgumentError('不能移入自身的子分组');
    final groups = {..._pinnedGroups, ..._hosts.map((h) => h.group)};
    if (groups.any(
      (g) =>
          g.toLowerCase() == target.toLowerCase() ||
          g.toLowerCase().startsWith('${target.toLowerCase()}/'),
    )) {
      throw ArgumentError('目标分组已存在');
    }
    String remap(String group) =>
        group == source || group.startsWith('$source/')
        ? '$target${group.substring(source.length)}'
        : group;
    _hosts = _hosts.map((h) => h.copyWith(group: remap(h.group))).toList();
    _pinnedGroups = {..._pinnedGroups.map(remap), target}.toList();
    await _storage.saveHosts(_hosts);
    await _storage.savePinnedGroups(_pinnedGroups);
    notifyListeners();
    await onMutation?.call();
  }

  /// Removing a folder never deletes connections or credentials.
  Future<void> dissolveGroup(String group) async {
    await _readyForWrite();
    bool inside(String value) => value == group || value.startsWith('$group/');
    _hosts = _hosts
        .map((h) => inside(h.group) ? h.copyWith(group: '') : h)
        .toList();
    _pinnedGroups.removeWhere(inside);
    await _storage.saveHosts(_hosts);
    await _storage.savePinnedGroups(_pinnedGroups);
    notifyListeners();
    await onMutation?.call();
  }

  Future<Host> duplicateHost(Host host) async {
    await _readyForWrite();
    final copy = Host.fromJson({
      ...host.toJson(),
      'id': const Uuid().v4(),
      'label': '${host.label} 副本',
      'createdAt': DateTime.now().toIso8601String(),
      'favorite': false,
      'lastUsedAt': null,
      'connectionCount': 0,
    });
    final password = await _storage.loadPassword(host.id);
    final sudo = await _storage.loadSudoPassword(host.id);
    if (sudo != null) await _storage.saveSudoPassword(copy.id, sudo);
    await addHost(copy, password: password);
    return copy;
  }

  void setSearch(String q) {
    _search = q;
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      _hosts = await _storage.loadHosts();
      _pinnedGroups = await _storage.loadPinnedGroups();
    } catch (e) {
      loadError = '无法读取连接数据：$e';
    }
    notifyListeners();
  }

  Future<void> _readyForWrite() async {
    await ready;
    if (loadError != null) throw StateError(loadError!);
  }

  Future<void> addHost(Host host, {String? password}) async {
    await _readyForWrite();
    if (password != null && password.isNotEmpty) {
      await _storage.savePassword(host.id, password);
    }
    _hosts.add(host);
    await _storage.saveHosts(_hosts);
    notifyListeners();
    await onMutation?.call();
  }

  Future<void> updateHost(Host host, {String? password}) async {
    await _readyForWrite();
    final idx = _hosts.indexWhere((h) => h.id == host.id);
    if (idx == -1) return;
    if (password != null && password.isNotEmpty) {
      await _storage.savePassword(host.id, password);
    }
    _hosts[idx] = host;
    await _storage.saveHosts(_hosts);
    notifyListeners();
    await onMutation?.call();
  }

  Future<void> deleteHost(String id) async {
    await _readyForWrite();
    onHostDeleted?.call(id);
    _hosts.removeWhere((h) => h.id == id);
    await _storage.saveHosts(_hosts);
    await _storage.deletePassword(id);
    await _storage.deleteSudoPassword(id);
    notifyListeners();
    await onMutation?.call();
  }

  Future<Map<String, String>> loadAllPasswords() async {
    final result = <String, String>{};
    for (final host in _hosts) {
      final pw = await _storage.loadPassword(host.id);
      if (pw != null) result['pw_${host.id}'] = pw;
    }
    return result;
  }

  Future<void> updateDetectedOs(String hostId, String os) async {
    final idx = _hosts.indexWhere((h) => h.id == hostId);
    if (idx == -1) return;
    _hosts[idx] = _hosts[idx].copyWith(detectedOs: os);
    await _storage.saveHosts(_hosts);
    notifyListeners();
    // intentionally does NOT call onMutation — local metadata only
  }

  Future<void> replaceAll(
    List<Host> hosts,
    Map<String, String> passwords,
  ) async {
    await _readyForWrite();
    final oldIds = _hosts.map((h) => h.id).toSet();
    final newIds = hosts.map((h) => h.id).toSet();
    final removedIds = oldIds.difference(newIds);
    for (final entry in passwords.entries) {
      if (!entry.key.startsWith('pw_')) continue;
      final hostId = entry.key.substring(3);
      if (newIds.contains(hostId)) {
        await _storage.savePassword(hostId, entry.value);
      }
    }
    await _storage.saveHosts(hosts);
    _pinnedGroups = await _storage.loadPinnedGroups();
    _hosts = List.of(hosts);
    for (final id in removedIds) {
      await _storage.deletePassword(id);
      await _storage.deleteSudoPassword(id);
    }
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_vault_provider.dart';

enum DataMode { local, cloudAccount }

/// Data stays local until a user explicitly signs in and saves a backup.
class SyncProvider extends ChangeNotifier {
  static const _modeKey = 'waytty.data_mode';
  final AccountVaultProvider account;
  late final Future<void> ready;
  DataMode _mode = DataMode.local;
  bool _disposed = false;
  int _modeGeneration = 0;
  int get modeGeneration => _modeGeneration;
  DataMode get mode => _mode;

  SyncProvider({AccountVaultProvider? account})
    : account = account ?? AccountVaultProvider() {
    this.account.addListener(_accountChanged);
    ready = _init();
  }

  void _accountChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    // Legacy sync-code settings never activate a network connection. Leave old
    // settings and local data intact so users can recover them with an old build.
    _mode = prefs.getString(_modeKey) == DataMode.cloudAccount.name
        ? DataMode.cloudAccount
        : DataMode.local;
    if (prefs.getString(_modeKey) == 'legacySync') {
      await prefs.setString(_modeKey, DataMode.local.name);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> selectMode(DataMode mode) async {
    await ready;
    if (_disposed) return;
    _modeGeneration++;
    _mode = mode;
    if (mode == DataMode.local) account.disconnect();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  @override
  void dispose() {
    _disposed = true;
    _modeGeneration++;
    account.removeListener(_accountChanged);
    account.dispose();
    super.dispose();
  }
}

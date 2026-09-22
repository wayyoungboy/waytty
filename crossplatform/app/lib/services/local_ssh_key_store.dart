import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host.dart';
import '../models/ssh_credentials.dart';
import 'account_vault_encryption.dart';
import 'manual_ssh_identity.dart';

/// App-owned encrypted records, explicitly saved by the user per connection.
/// The unlock password and decrypted records exist only in this process.
/// This store never accesses the OS keychain, key files, SSH agent or cloud.
class LocalSshKeyStore extends ChangeNotifier {
  static const storageKey = 'waytty.local_ssh_keys.v1';
  static const _domain = 'waytty-local-ssh-keys-v1';
  static const _check = 'waytty local SSH key store';
  Future<void>? _loaded;
  Future<void> _tail = Future.value();
  String? _verifier;
  String? _password;
  Map<String, String> _entries = {};
  final _cache = <String, Map<String, dynamic>>{};
  int _generation = 0;

  bool get configured => _verifier != null;
  bool get unlocked => _password != null;
  bool hasKey(String hostId) => _entries.containsKey(hostId);

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) async {
      await load();
      return operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> load() => _loaded ??= _load();
  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(storageKey);
    if (raw == null) return;
    try {
      if (raw.length > AccountVaultEncryption.maxEncodedLength) {
        throw const FormatException();
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1 || data['verifier'] is! String) {
        throw const FormatException();
      }
      final entries = Map<String, String>.from(data['entries'] as Map);
      if (entries.values.any(
        (v) => !v.startsWith(AccountVaultEncryption.prefix),
      )) {
        throw const FormatException();
      }
      _verifier = data['verifier'] as String;
      _entries = entries;
    } catch (_) {
      throw const FormatException('Saved private keys are damaged.');
    }
  }

  Future<void> _write(String? verifier, Map<String, String> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      'version': 1,
      'verifier': verifier,
      'entries': entries,
    });
    if (encoded.length > AccountVaultEncryption.maxEncodedLength) {
      throw StateError('Saved private keys are too large.');
    }
    final written = verifier == null
        ? await prefs.remove(storageKey)
        : await prefs.setString(storageKey, encoded);
    if (!written) throw StateError('Could not save private keys.');
    _verifier = verifier;
    _entries = entries;
    notifyListeners();
  }

  Future<void> unlock(String password) {
    final generation = _generation;
    return _serial(() async {
      if (generation != _generation) throw const AuthenticationCancelled();
      if (_entries.isEmpty) {
        if (password.runes.length < 8) {
          throw const FormatException('Use at least 8 characters.');
        }
        final verifier = await AccountVaultEncryption.encrypt(
          _check,
          password,
          '$_domain:check',
        );
        if (generation != _generation) throw const AuthenticationCancelled();
        // Persist the verifier atomically with the first saved key. An
        // abandoned setup must not leave an empty, locked store on disk.
        _verifier = verifier;
      } else {
        final check = await AccountVaultEncryption.decrypt(
          _verifier!,
          password,
          '$_domain:check',
        );
        if (check != _check) {
          throw const FormatException(
            'Incorrect vault password or damaged data.',
          );
        }
      }
      if (generation != _generation) throw const AuthenticationCancelled();
      _password = password;
      notifyListeners();
    });
  }

  void lock() {
    _generation++;
    _password = null;
    if (_entries.isEmpty) _verifier = null;
    _cache.clear();
    notifyListeners();
  }

  // Capture values, not the mutable Host object. Renaming a connection is safe;
  // changing its destination, identity or selected key requires new input.
  static String _binding(Host host) => jsonEncode([
    host.id,
    host.host,
    host.port,
    host.username,
    host.protocol.name,
    host.authType.name,
    host.keyId,
  ]);

  Future<SshCredentials?> read(Host host) {
    final id = host.id;
    final binding = _binding(host);
    return _serial(() async {
      final encoded = _entries[id];
      if (encoded == null) return null;
      final password = _password;
      if (password == null) throw const ManualAuthenticationRequired();
      final generation = _generation;
      var data = _cache[id];
      if (data == null) {
        final decoded = await AccountVaultEncryption.decrypt(
          encoded,
          password,
          '$_domain:key:$id',
        );
        if (generation != _generation) throw const AuthenticationCancelled();
        try {
          data = jsonDecode(decoded) as Map<String, dynamic>;
          if (data['privateKey'] is! String ||
              data['binding'] is! String ||
              (data['passphrase'] != null && data['passphrase'] is! String) ||
              (data['certificate'] != null && data['certificate'] is! String)) {
            throw const FormatException();
          }
        } catch (_) {
          throw const FormatException('Saved private keys are damaged.');
        }
        _cache[id] = data;
      }
      if (data['binding'] != binding) return null;
      return SshCredentials(
        privateKey: data['privateKey'] as String,
        passphrase: data['passphrase'] as String?,
        certificate: data['certificate'] as String?,
      );
    });
  }

  Future<void> save(
    Host host,
    SshCredentials input, {
    bool Function()? cancelled,
  }) {
    if (host.authType == AuthType.password) {
      throw ArgumentError('This store only saves private keys.');
    }
    parseManualSshIdentity(host, input);
    final id = host.id;
    final data = <String, dynamic>{
      'binding': _binding(host),
      'privateKey': input.privateKey,
      'passphrase': input.passphrase,
      'certificate': input.certificate,
    };
    final generation = _generation;
    return _serial(() async {
      if (generation != _generation || cancelled?.call() == true) {
        throw const AuthenticationCancelled();
      }
      final password = _password;
      if (password == null) throw const ManualAuthenticationRequired();
      final encoded = await AccountVaultEncryption.encrypt(
        jsonEncode(data),
        password,
        '$_domain:key:$id',
      );
      if (generation != _generation || cancelled?.call() == true) {
        throw const AuthenticationCancelled();
      }
      await _write(_verifier, {..._entries, id: encoded});
      if (generation == _generation) _cache[id] = data;
    });
  }

  /// Connection deletion works while locked; it never decrypts the record.
  Future<void> remove(String hostId) => _serial(() async {
    if (!_entries.containsKey(hostId)) return;
    final entries = {..._entries}..remove(hostId);
    _cache.remove(hostId);
    await _write(entries.isEmpty ? null : _verifier, entries);
    if (entries.isEmpty) lock();
  });
}

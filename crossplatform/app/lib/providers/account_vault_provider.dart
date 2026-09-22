import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/account_vault_encryption.dart';
import '../services/account_vault_service.dart';
import '../services/sync_service.dart';

/// Email accounts and client-encrypted backups. Authentication and vault
/// passwords have separate purposes; neither password is persisted locally.
class AccountVaultProvider extends ChangeNotifier {
  final AccountCloudConfig config;
  final AccountVaultBackend Function() _createBackend;
  AccountVaultBackend? _backend;
  String? _vaultPassword;
  int? _revision;
  bool? _vaultExists;
  String? pendingEmail;
  DateTime? _resendAt;
  final DateTime Function() _now;
  int _generation = 0;
  bool _disposed = false;
  bool busy = false;
  String? message;
  bool hasError = false;

  AccountVaultProvider({
    this.config = const AccountCloudConfig(),
    AccountVaultBackend Function()? createBackend,
    DateTime Function()? now,
  }) : _createBackend =
           createBackend ?? (() => HttpAccountVaultService(config)),
       _now = now ?? DateTime.now;

  bool get signedIn => _backend?.userId != null;
  String? get email => _backend?.email;
  bool get unlocked => signedIn && _vaultPassword != null;
  bool get hasRemoteVault => (_revision ?? 0) > 0;
  bool get creatingVault => _vaultExists == false;
  int get resendSeconds => _resendAt == null
      ? 0
      : ((_resendAt!.difference(_now()).inMilliseconds / 1000).ceil()).clamp(
          0,
          60,
        );

  static bool validEmail(String email) =>
      email.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  static bool validPassword(String password) =>
      password.runes.length > 8 && password.runes.length <= 16;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(Future<void> Function(int generation) operation) async {
    if (_disposed || busy) return;
    busy = true;
    message = null;
    hasError = false;
    final generation = _generation;
    _notify();
    try {
      await operation(generation);
    } catch (error) {
      if (generation != _generation || _disposed) return;
      hasError = true;
      if (!signedIn) {
        _vaultPassword = null;
        _revision = null;
        _vaultExists = null;
      }
      // Do not surface SDK/network exception bodies, which can include tokens
      // or payloads. Only fixed, translated product messages reach the UI.
      if (error is AccountCloudException && error.code == 'revision_conflict') {
        _vaultPassword = null;
        _revision = null;
        message = 'Cloud data changed. Unlock again before saving.';
      } else if (error is AccountCloudException &&
          (error.status == 401 ||
              error.code == 'verification_failed' ||
              error.code == 'email_not_confirmed')) {
        message = pendingEmail != null
            ? 'Verification failed or expired. Check the latest email or request a new code.'
            : 'Sign-in failed. Check your email, password and email confirmation.';
      } else if (error is FormatException) {
        message = 'Incorrect vault password or damaged data.';
      } else {
        message =
            'Cloud request failed. Your local connections are unchanged. Please retry.';
      }
    } finally {
      if (generation == _generation && !_disposed) {
        busy = false;
        _notify();
      }
    }
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> authenticate(
    String email,
    String password, {
    bool register = false,
  }) async {
    email = email.trim().toLowerCase();
    if (!validEmail(email) || !validPassword(password)) {
      message = 'Enter a valid email and a password of 9–16 characters.';
      hasError = true;
      _notify();
      return;
    }
    if (!config.isConfigured) {
      message =
          'Cloud service is not configured in this build. Local mode is available.';
      hasError = true;
      _notify();
      return;
    }
    await _run((generation) async {
      final backend = _backend ??= _createBackend();
      _vaultPassword = null;
      _revision = null;
      _vaultExists = null;
      if (register) {
        final active = await backend.signUp(email, password);
        if (!_current(generation)) return;
        if (active) {
          // Fail closed if the operator accidentally disabled confirmation.
          disconnect();
          message =
              'Email verification must be enabled for this cloud service.';
          hasError = true;
          _notify();
          return;
        }
        pendingEmail = email;
        _resendAt = _now().add(const Duration(seconds: 60));
        message =
            'Enter the verification code from your email to activate your account.';
      } else {
        try {
          await backend.signIn(email, password);
        } on AccountCloudException catch (error) {
          if (_current(generation) && error.code == 'email_not_confirmed') {
            pendingEmail = email;
            _resendAt = _now().add(const Duration(seconds: 60));
          }
          rethrow;
        }
        if (!_current(generation)) return;
        pendingEmail = null;
        _resendAt = null;
        message = 'Signed in. Unlock your vault to continue.';
      }
      if (backend.userId != null) {
        final record = await backend.fetch();
        if (!_current(generation)) return;
        _vaultExists = record != null;
      }
    });
  }

  Future<void> verifyEmail(String code) async {
    final email = pendingEmail;
    code = code.trim();
    if (email == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      message = 'Enter the 6-digit email verification code.';
      hasError = true;
      _notify();
      return;
    }
    await _run((generation) async {
      final backend = _backend!;
      await backend.verifyEmail(email, code);
      if (!_current(generation)) return;
      pendingEmail = null;
      _resendAt = null;
      message = 'Email verified. Unlock your vault to continue.';
      final record = await backend.fetch();
      if (_current(generation)) _vaultExists = record != null;
    });
  }

  Future<void> resendVerification() async {
    if (pendingEmail == null || resendSeconds > 0) return;
    await _run((generation) async {
      // Enforce a local cooldown even when delivery fails; server-side rate
      // limits remain authoritative across devices and app restarts.
      _resendAt = _now().add(const Duration(seconds: 60));
      await _backend!.resendVerification(pendingEmail!);
      if (_current(generation)) {
        message =
            'If this email is awaiting verification, a new code has been sent. Check your spam folder too.';
      }
    });
  }

  Future<void> unlock(String password) async {
    if (!signedIn) return;
    if (!validPassword(password)) {
      message = 'Use a vault password of 9–16 characters.';
      hasError = true;
      _notify();
      return;
    }
    await _run((generation) async {
      _vaultPassword = null;
      _revision = null;
      final backend = _backend!;
      final record = await backend.fetch();
      if (!_current(generation)) return;
      if (record != null) {
        final plaintext = await AccountVaultEncryption.decrypt(
          record.ciphertext,
          password,
          backend.userId!,
        );
        SyncService.parsePayload(plaintext);
      }
      if (!_current(generation)) return;
      _vaultPassword = password;
      _vaultExists = record != null;
      _revision = record?.revision ?? 0;
      message = record == null
          ? 'No cloud backup yet. Save your local connections to create one.'
          : 'Vault unlocked. Choose Save or Restore.';
    });
  }

  Future<void> save(Future<String> Function() snapshot) async {
    if (!unlocked) return;
    await _run((generation) async {
      final backend = _backend!;
      final userId = backend.userId!;
      final password = _vaultPassword!;
      final revision = _revision!;
      var plaintext = await snapshot();
      if (!_current(generation)) return;
      // A missing in-memory password after restart is not a deletion request.
      // Read only the explicitly unlocked cloud backup, never local keychains.
      // Revision checks prevent merging against a different device's update.
      final record = await backend.fetch();
      if (!_current(generation)) return;
      if ((record?.revision ?? 0) != revision) {
        throw const AccountCloudException(409, 'revision_conflict');
      }
      if (record != null) {
        final previous = SyncService.parsePayload(await AccountVaultEncryption.decrypt(
          record.ciphertext, password, userId,
        ));
        if (!_current(generation)) return;
        final current = SyncService.parsePayload(plaintext);
        final passwords = <String, String>{};
        for (final host in current.hosts) {
          final key = 'pw_${host.id}';
          // Explicit values (including empty passwords) replace the old value;
          // deleting a host also deletes its password from the next backup.
          final value = current.passwords[key] ?? previous.passwords[key];
          if (value != null) passwords[key] = value;
        }
        plaintext = SyncService.buildPayload(hosts: current.hosts,
            passwords: passwords, workspace: current.workspace);
      }
      final ciphertext = await AccountVaultEncryption.encrypt(
        plaintext,
        password,
        userId,
      );
      // Going offline during KDF or snapshot collection must prevent upload.
      if (!_current(generation)) return;
      final newRevision = await backend.save(ciphertext, revision);
      if (!_current(generation)) return;
      _revision = newRevision;
      _vaultExists = true;
      message = 'Encrypted connections saved to your cloud account.';
    });
  }

  Future<SyncPayload?> download() async {
    if (!unlocked) return null;
    SyncPayload? result;
    await _run((generation) async {
      final backend = _backend!;
      final password = _vaultPassword!;
      final userId = backend.userId!;
      final record = await backend.fetch();
      if (!_current(generation)) return;
      if (record == null) {
        message =
            'No cloud backup yet. Save your local connections to create one.';
        return;
      }
      final plaintext = await AccountVaultEncryption.decrypt(
        record.ciphertext,
        password,
        userId,
      );
      if (!_current(generation)) return;
      result = SyncService.parsePayload(plaintext);
      _revision = record.revision;
    });
    return result;
  }

  void reportRestore({required bool success}) {
    message = success
        ? 'Cloud connections restored to this device.'
        : 'Restore stopped. Local data changed or could not be saved.';
    hasError = !success;
    _notify();
  }

  /// Local sign-out also invalidates all in-flight work. It never deletes a
  /// local connection or remote vault. Session revocation is attempted once.
  void disconnect() {
    _generation++;
    _vaultPassword = null;
    _revision = null;
    _vaultExists = null;
    pendingEmail = null;
    _resendAt = null;
    final backend = _backend;
    _backend = null;
    busy = false;
    message = null;
    hasError = false;
    if (backend != null) unawaited(backend.dispose().catchError((Object _) {}));
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }
}

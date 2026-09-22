import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/account_vault_provider.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/account_vault_service.dart';
import 'package:yourssh/services/sync_service.dart';

class FakeAccountBackend implements AccountVaultBackend {
  @override
  String? userId;
  @override
  String? email;
  AccountVaultRecord? record;
  bool confirmationRequired = false;
  int resends = 0;
  int verifications = 0;
  int signIns = 0;
  int saves = 0;
  bool disposed = false;
  Completer<void>? fetchGate;
  @override
  Future<void> signIn(String email, String password) async {
    signIns++;
    userId = 'fixture-user';
    this.email = email;
  }

  @override
  Future<bool> signUp(String email, String password) async {
    if (confirmationRequired) return false;
    await signIn(email, password);
    return true;
  }

  @override
  Future<void> verifyEmail(String email, String code) async {
    verifications++;
    if (code != '123456') throw const AccountCloudException(400, 'verification_failed');
    userId = 'fixture-user';
    this.email = email;
  }

  @override
  Future<void> resendVerification(String email) async {
    resends++;
  }

  @override
  Future<AccountVaultRecord?> fetch() async {
    if (fetchGate != null) await fetchGate!.future;
    return record;
  }

  @override
  Future<int> save(String ciphertext, int expectedRevision) async {
    saves++;
    if ((record?.revision ?? 0) != expectedRevision) {
      throw const AccountCloudException(409, 'revision_conflict');
    }
    record = AccountVaultRecord(ciphertext, expectedRevision + 1);
    return record!.revision;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    userId = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config = AccountCloudConfig(
    url: 'https://fixture.invalid',
  );
  late FakeAccountBackend backend;
  late AccountVaultProvider account;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAccountBackend();
    account = AccountVaultProvider(
      config: config,
      createBackend: () => backend,
    );
  });
  tearDown(() => account.dispose());

  test(
    'email-only accounts; rejects 8/17 and accepts 9/16 characters',
    () async {
      expect(AccountVaultProvider.validEmail('username'), false);
      expect(AccountVaultProvider.validEmail('a@b'), false);
      expect(AccountVaultProvider.validEmail('a @example.com'), false);
      expect(AccountVaultProvider.validEmail('a+test@example.com'), true);
      for (final length in [8, 17]) {
        await account.authenticate('a@example.com', 'a' * length);
        expect(account.hasError, true);
        expect(backend.signIns, 0);
      }
      expect(AccountVaultProvider.validPassword('a' * 9), true);
      expect(AccountVaultProvider.validPassword('a' * 16), true);
      await account.authenticate('  Person@Example.com ', 'a' * 9);
      expect(account.email, 'person@example.com');
      expect(account.creatingVault, true);
      expect(backend.saves, 0);
    },
  );

  test('email confirmation does not unlock or create a cloud record', () async {
    backend.confirmationRequired = true;
    await account.authenticate('a@example.com', 'a' * 12, register: true);
    expect(account.signedIn, false);
    expect(account.pendingEmail, 'a@example.com');
    expect(backend.record, isNull);
    await account.verifyEmail('12345');
    expect(backend.verifications, 0);
    await account.verifyEmail('654321');
    expect(account.hasError, true);
    expect(account.signedIn, false);
    await account.verifyEmail('123456');
    expect(account.signedIn, true);
    expect(account.pendingEmail, isNull);
    expect(account.unlocked, false);
    expect(backend.saves, 0);
  });

  test(
    'registration refuses a backend that skips email verification',
    () async {
      await account.authenticate(
        'a@example.com',
        'login-pass-123',
        register: true,
      );
      expect(account.hasError, true);
      expect(account.signedIn, false);
      expect(backend.disposed, true);
    },
  );

  test('resending verification has a 60-second cooldown', () async {
    var now = DateTime.utc(2026, 9, 17);
    final pending = AccountVaultProvider(
      config: config,
      createBackend: () => backend,
      now: () => now,
    );
    backend.confirmationRequired = true;
    await pending.authenticate(
      'a@example.com',
      'login-pass-123',
      register: true,
    );
    await pending.resendVerification();
    expect(backend.resends, 0);
    now = now.add(const Duration(seconds: 60));
    await pending.resendVerification();
    expect(backend.resends, 1);
    await pending.resendVerification();
    expect(backend.resends, 1);
    pending.dispose();
  });

  test(
    'backup survives sign-out; wrong vault password cannot overwrite it',
    () async {
      await account.authenticate('a@example.com', 'login-pass-123');
      await account.unlock('vault-pass-123');
      await account.save(
        () async => SyncService.buildPayload(
          hosts: [],
          passwords: {'pw_fixture': 'secret'},
        ),
      );
      expect(backend.record!.ciphertext, isNot(contains('secret')));
      final restored = await account.download();
      expect(restored!.passwords['pw_fixture'], 'secret');
      account.disconnect();
      expect(account.signedIn, false);
      expect(account.unlocked, false);
      expect(backend.record, isNotNull);
      await account.authenticate('a@example.com', 'login-pass-123');
      await account.unlock('wrong-password');
      expect(account.hasError, true);
      expect(account.unlocked, false);
      await account.save(() async => 'must-not-upload');
      expect(backend.saves, 1);
    },
  );

  test(
    'stale writes preserve cloud data and require unlocking again',
    () async {
      await account.authenticate('a@example.com', 'login-pass-123');
      await account.unlock('vault-pass-123');
      backend.record = AccountVaultRecord('other-device-ciphertext', 1);
      await account.save(
        () async => SyncService.buildPayload(hosts: [], passwords: {}),
      );
      expect(account.hasError, true);
      expect(account.unlocked, false);
      expect(backend.record!.ciphertext, 'other-device-ciphertext');
    },
  );

  test(
    'switching offline during snapshot prevents an eventual upload',
    () async {
      await account.authenticate('a@example.com', 'login-pass-123');
      await account.unlock('vault-pass-123');
      final snapshot = Completer<String>();
      final saving = account.save(() => snapshot.future);
      account.disconnect();
      snapshot.complete(SyncService.buildPayload(hosts: [], passwords: {}));
      await saving;
      expect(backend.saves, 0);
      expect(account.busy, false);
      expect(account.signedIn, false);
      expect(account.message, isNull);
    },
  );

  test('restart preserves cloud passwords; explicit replacement and host deletion still work', () async {
    final hosts = HostProvider(StorageService());
    addTearDown(hosts.dispose);
    await hosts.ready;
    Host host(String id) => Host(id: id, label: id, host: 'fixture.invalid', username: 'fixture');
    await hosts.addHost(host('keep'), password: 'fixture-original');
    await hosts.addHost(host('remove'), password: 'fixture-removed');
    await account.authenticate('a@example.com', 'login-pass-123');
    await account.unlock('vault-pass-123');
    Future<String> snapshot(HostProvider p) async => SyncService.buildPayload(
      hosts: p.allHosts, passwords: await p.loadAllPasswords(), workspace: {'fixture': true});
    await account.save(() => snapshot(hosts));

    final restarted = HostProvider(StorageService());
    addTearDown(restarted.dispose);
    await restarted.ready;
    expect(await restarted.loadAllPasswords(), isEmpty);
    await account.save(() => snapshot(restarted));
    expect(account.hasError, false);
    final restored = (await account.download())!;
    expect(restored.passwords, {'pw_keep': 'fixture-original', 'pw_remove': 'fixture-removed'});
    expect(restored.workspace, {'fixture': true});
    // Cloud merge does not repopulate any local authentication store.
    expect(await restarted.loadAllPasswords(), isEmpty);

    await account.save(() async => SyncService.buildPayload(
      hosts: [host('keep')], passwords: {'pw_keep': 'fixture-replacement'}));
    expect((await account.download())!.passwords, {'pw_keep': 'fixture-replacement'});
    await account.save(() async => SyncService.buildPayload(
      hosts: [host('keep')], passwords: {'pw_keep': ''}));
    expect((await account.download())!.passwords, {'pw_keep': ''});
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('sign-out during cloud merge prevents upload and preserves prior ciphertext', () async {
    await account.authenticate('a@example.com', 'login-pass-123');
    await account.unlock('vault-pass-123');
    await account.save(() async => SyncService.buildPayload(hosts: [], passwords: {}));
    final before = backend.record;
    backend.fetchGate = Completer<void>();
    final saving = account.save(() async => SyncService.buildPayload(hosts: [], passwords: {}));
    await Future<void>.delayed(Duration.zero);
    account.disconnect();
    backend.fetchGate!.complete();
    await saving;
    expect(backend.record, same(before));
    expect(backend.saves, 1);
  });

  test('late unlock response after sign-out is ignored', () async {
    await account.authenticate('a@example.com', 'login-pass-123');
    backend.fetchGate = Completer<void>();
    final unlocking = account.unlock('vault-pass-123');
    account.disconnect();
    backend.fetchGate!.complete();
    await unlocking;
    expect(account.unlocked, false);
    expect(account.message, isNull);
  });

}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_credentials.dart';
import 'package:yourssh/services/local_ssh_key_store.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/providers/host_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = File('test/fixtures/keys/id_ed25519_enc').readAsStringSync();
  final input = SshCredentials(privateKey: key, passphrase: 'test-passphrase');
  Host host(String id) => Host(
    id: id,
    label: id,
    host: 'fixture.invalid',
    username: 'fixture',
    authType: AuthType.privateKey,
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => fail('Must not access OS secure storage'),
        );
  });

  test(
    'keys persist encrypted, restart locked, and bind to exact destination',
    () async {
      final first = LocalSshKeyStore();
      await first.unlock('fixture-unlock-password');
      final h = host('one');
      await first.save(h, input);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(LocalSshKeyStore.storageKey)!;
      for (final secret in [
        key,
        'test-passphrase',
        'fixture-unlock-password',
        'fixture.invalid',
      ]) {
        expect(raw, isNot(contains(secret)));
      }
      final restarted = LocalSshKeyStore();
      await restarted.load();
      expect(restarted.hasKey(h.id), isTrue);
      expect(restarted.unlocked, isFalse);
      await expectLater(
        restarted.read(h),
        throwsA(isA<ManualAuthenticationRequired>()),
      );
      await expectLater(
        restarted.unlock('wrong-password'),
        throwsFormatException,
      );
      expect(restarted.unlocked, isFalse);
      await restarted.unlock('fixture-unlock-password');
      expect((await restarted.read(h))!.privateKey, key);
      expect(
        (await restarted.read(h.copyWith(label: 'renamed')))!.passphrase,
        'test-passphrase',
      );
      for (final changed in [
        h.copyWith(host: 'other.invalid'),
        h.copyWith(port: 2222),
        h.copyWith(username: 'other'),
        h.copyWith(authType: AuthType.certificate),
        h.copyWith(keyId: 'other'),
      ]) {
        expect(await restarted.read(changed), isNull);
      }
      restarted.lock();
      await expectLater(
        restarted.read(h),
        throwsA(isA<ManualAuthenticationRequired>()),
      );
      await restarted.remove(h.id); // does not need unlock
      expect(prefs.containsKey(LocalSshKeyStore.storageKey), isFalse);
      expect(restarted.configured, isFalse);
    },
  );

  test(
    'ciphertext copied to a different connection cannot be decrypted',
    () async {
      final store = LocalSshKeyStore();
      await store.unlock('fixture-unlock-password');
      await store.save(host('one'), input);
      final prefs = await SharedPreferences.getInstance();
      final raw =
          jsonDecode(prefs.getString(LocalSshKeyStore.storageKey)!)
              as Map<String, dynamic>;
      (raw['entries'] as Map)['two'] = (raw['entries'] as Map)['one'];
      await prefs.setString(LocalSshKeyStore.storageKey, jsonEncode(raw));
      final restarted = LocalSshKeyStore();
      await restarted.unlock('fixture-unlock-password');
      await expectLater(restarted.read(host('two')), throwsFormatException);
      expect((await restarted.read(host('one')))!.privateKey, key);
    },
  );

  test('lock cancels queued unlock and invalid keys never persist', () async {
    final store = LocalSshKeyStore();
    final unlocking = store.unlock('fixture-unlock-password');
    store.lock();
    await expectLater(unlocking, throwsA(isA<AuthenticationCancelled>()));
    expect(store.unlocked, isFalse);
    expect(
      () => store.save(
        host('one'),
        const SshCredentials(privateKey: 'bad-secret-fixture'),
      ),
      throwsFormatException,
    );
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        LocalSshKeyStore.storageKey,
      ),
      isFalse,
    );
  });

  test(
    'deleting or replacing connections removes saved keys while locked',
    () async {
      final storage = StorageService();
      final hosts = HostProvider(storage);
      await hosts.ready;
      final a = host('one');
      final b = host('two');
      await hosts.addHost(a);
      await hosts.addHost(b);
      await storage.privateKeys.unlock('fixture-unlock-password');
      await storage.privateKeys.save(a, input);
      await storage.privateKeys.save(b, input);
      storage.clearSessionSecrets();
      await hosts.deleteHost(a.id);
      expect(storage.privateKeys.hasKey(a.id), isFalse);
      expect(storage.privateKeys.hasKey(b.id), isTrue);
      await hosts.replaceAll([], {});
      expect(storage.privateKeys.hasKey(b.id), isFalse);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          LocalSshKeyStore.storageKey,
        ),
        isFalse,
      );
      expect(await hosts.loadAllPasswords(), isEmpty);
    },
  );
}

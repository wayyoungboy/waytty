import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final calls = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pw_old': 'legacy',
      'pp_key': 'legacy-key',
    });
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          throw PlatformException(code: 'forbidden-keychain-access');
        });
  });
  tearDown(() {
    expect(
      calls,
      isEmpty,
      reason: 'No credential API may access the OS keychain',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('old credentials are never read or migrated', () async {
    final s = StorageService();
    expect(await s.loadPassword('old'), isNull);
    expect(await s.loadPassphrase('key'), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('pw_old'),
      'legacy',
    );
  });

  test(
    'manually provided values remain in memory without persistence',
    () async {
      final s = StorageService();
      await s.savePassword('new', 'entered-password');
      await s.savePassphrase('new', 'entered-passphrase');
      await s.saveSudoPassword('new', 'entered-sudo');
      await s.saveGenericSecret('proxy', 'entered-proxy');
      expect(await s.loadPassword('new'), 'entered-password');
      expect(await s.loadPassphrase('new'), 'entered-passphrase');
      expect(await s.loadSudoPassword('new'), 'entered-sudo');
      expect(await s.loadGenericSecret('proxy'), 'entered-proxy');
      expect((await SharedPreferences.getInstance()).getKeys(), {
        'pw_old',
        'pp_key',
      });
      final restarted = StorageService();
      expect(await restarted.loadPassword('new'), isNull);
      expect(await restarted.loadPassphrase('new'), isNull);
      s.clearSessionSecrets();
      expect(await s.loadPassword('new'), isNull);
      expect(await s.loadGenericSecret('proxy'), isNull);
    },
  );

  test('forgetting values never deletes existing OS credentials', () async {
    final s = StorageService();
    await s.savePassword('new', 'value');
    await s.deletePassword('new');
    await s.deletePassword('old');
    await s.deleteGenericSecret('pp_key');
    await s.deleteSudoPassword('old');
    await s.deleteGenericSecret('proxy');
    expect(await s.loadPassword('new'), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('pw_old'),
      'legacy',
    );
  });
}

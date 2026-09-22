import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/sync_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('new installs start offline with no account session', () async {
    SharedPreferences.setMockInitialValues({});
    final sync = SyncProvider();
    await sync.ready;
    expect(sync.mode, DataMode.local);
    expect(sync.account.signedIn, false);
    sync.dispose();
  });
  test(
    'legacy configuration becomes local without modifying saved data',
    () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': 'https://old.invalid',
        'supabase_anon_key': 'old-public-key',
        'waytty.data_mode': 'legacySync',
        'hosts': 'existing-local-data',
      });
      final sync = SyncProvider();
      await sync.ready;
      expect(sync.mode, DataMode.local);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('waytty.data_mode'), 'local');
      expect(prefs.getString('hosts'), 'existing-local-data');
      expect(prefs.getString('supabase_url'), 'https://old.invalid');
      sync.dispose();
    },
  );
  test(
    'mode changes survive restart and invalidate pending restores',
    () async {
      SharedPreferences.setMockInitialValues({});
      final sync = SyncProvider();
      final original = sync.modeGeneration;
      await sync.selectMode(DataMode.cloudAccount);
      expect(sync.modeGeneration, greaterThan(original));
      sync.dispose();
      final restarted = SyncProvider();
      await restarted.ready;
      expect(restarted.mode, DataMode.cloudAccount);
      expect(restarted.account.signedIn, false);
      await restarted.selectMode(DataMode.local);
      expect(
        (await SharedPreferences.getInstance()).getString('waytty.data_mode'),
        'local',
      );
      restarted.dispose();
    },
  );
}

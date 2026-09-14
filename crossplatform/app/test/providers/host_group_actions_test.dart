import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import '../helpers/secure_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installSecureStoreMock();
  });

  test(
    'rename moves nested groups and keeps similarly prefixed groups',
    () async {
      final provider = HostProvider(StorageService());
      await provider.addGroup('prod/empty');
      await provider.addHost(
        Host(id: 'a', label: 'A', host: 'a', username: 'u', group: 'prod/db'),
      );
      await provider.addHost(
        Host(id: 'b', label: 'B', host: 'b', username: 'u', group: 'prod2'),
      );
      await provider.renameGroup('prod', 'work/production');
      expect(provider.byId('a')!.group, 'work/production/db');
      expect(provider.byId('b')!.group, 'prod2');
      expect(provider.pinnedGroups, contains('work/production/empty'));
      await expectLater(
        provider.renameGroup('prod2', 'work'),
        throwsArgumentError,
      );
      final loaded = HostProvider(StorageService());
      await loaded.ready;
      expect(loaded.byId('a')!.group, 'work/production/db');
      provider.dispose();
      loaded.dispose();
    },
  );

  test(
    'dissolving a group preserves nested hosts and their credentials',
    () async {
      final storage = StorageService();
      final provider = HostProvider(storage);
      await provider.addHost(
        Host(id: 'a', label: 'A', host: 'a', username: 'u', group: 'prod/db'),
        password: 'fixture',
      );
      await provider.addGroup('prod/empty');
      await provider.dissolveGroup('prod');
      expect(provider.byId('a')!.group, '');
      expect(provider.pinnedGroups, isEmpty);
      expect(await storage.loadPassword('a'), 'fixture');
      provider.dispose();
    },
  );

  test(
    'copy gets an independent identity and preserves protected credentials',
    () async {
      final storage = StorageService();
      final provider = HostProvider(storage);
      final original = Host(
        id: 'a',
        label: 'A',
        host: 'a',
        username: 'u',
        group: 'prod',
        note: '备注',
        favorite: true,
        connectionCount: 8,
      );
      await provider.addHost(original, password: 'fixture');
      await storage.saveSudoPassword(original.id, 'sudo-fixture');
      final copy = await provider.duplicateHost(original);
      expect(copy.id, isNot(original.id));
      expect(copy.note, '备注');
      expect(copy.connectionCount, 0);
      expect(copy.favorite, false);
      expect(await storage.loadPassword(copy.id), 'fixture');
      expect(await storage.loadSudoPassword(copy.id), 'sudo-fixture');
      provider.dispose();
    },
  );
}

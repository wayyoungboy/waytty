import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/p2p_sync_encryption.dart';
import 'package:yourssh/services/sync_service.dart';

void main() {
  group('SyncService.buildPayload', () {
    test('serialises hosts and passwords into JSON', () async {
      final host = Host(
        id: 'h1',
        label: 'Test',
        host: 'example.com',
        port: 22,
        username: 'user',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final payload = SyncService.buildPayload(
        hosts: [host],
        passwords: {'pw_h1': 'secret'},
      );
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded['hosts'], hasLength(1));
      expect((decoded['hosts'][0] as Map)['id'], 'h1');
      expect(decoded['passwords']['pw_h1'], 'secret');
      expect(decoded['updated_at'], isNotNull);
    });
  });

  group('SyncService encrypt/decrypt roundtrip', () {
    test(
      'buildPayload → encrypt → decrypt → parsePayload is lossless',
      () async {
        final host = Host(
          id: 'abc',
          label: 'My Server',
          host: '1.2.3.4',
          port: 22,
          username: 'root',
          createdAt: DateTime.utc(2026, 1, 1),
        );
        final code = P2PSyncEncryption.generateKey();
        final payload = SyncService.buildPayload(
          hosts: [host],
          passwords: {'pw_abc': 'pass123'},
        );
        final encrypted = await P2PSyncEncryption.encrypt(payload, code);
        final decrypted = await P2PSyncEncryption.decrypt(encrypted, code);
        final result = SyncService.parsePayload(decrypted);
        expect(result.hosts, hasLength(1));
        expect(result.hosts.first.id, 'abc');
        expect(result.passwords['pw_abc'], 'pass123');
      },
    );
  });

}

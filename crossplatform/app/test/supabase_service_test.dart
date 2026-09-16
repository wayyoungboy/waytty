import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yourssh/services/supabase_service.dart';

void main() {
  test('stores url, anonKey and syncCode via constructor', () {
    final svc = SupabaseService(
      'https://abc.supabase.co',
      'anon-key-123',
      'ABCD2345EFGH',
    );
    expect(svc.url, 'https://abc.supabase.co');
    expect(svc.anonKey, 'anon-key-123');
    expect(svc.syncCode, 'ABCD2345EFGH');
  });

  test('migrationSql contains sync_data table definition', () {
    expect(SupabaseService.migrationSql, contains('sync_data'));
    expect(SupabaseService.migrationSql, contains('row level security'));
  });

  test(
    'cloud requests send derived capability, never the encryption code',
    () async {
      const code = 'ABCD2345EFGH';
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://fixture.invalid',
        'fixture-anon',
        httpClient: MockClient((request) async {
          requests.add(request);
          final endpoint = request.url.pathSegments.last;
          return http.Response(
            endpoint == 'waytty_sync_get'
                ? jsonEncode({
                    'payload': 'v1:encrypted-fixture',
                    'updated_at': '2026-09-13T00:00:00Z',
                  })
                : endpoint == 'waytty_sync_ping'
                ? '1'
                : '',
            endpoint == 'waytty_sync_put' || endpoint == 'waytty_sync_delete'
                ? 204
                : 200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final service = SupabaseService('', '', code, client: client);
      expect(
        (await service.testConnection()).$1,
        TestConnectionOutcome.connected,
      );
      await service.upsertPayload('v1:encrypted-fixture');
      expect(await service.fetchPayload(), 'v1:encrypted-fixture');
      expect(await service.fetchUpdatedAt(), DateTime.utc(2026, 9, 13));
      await service.deleteRow();
      expect(requests.map((r) => r.url.path), [
        '/rest/v1/rpc/waytty_sync_ping',
        '/rest/v1/rpc/waytty_sync_put',
        '/rest/v1/rpc/waytty_sync_get',
        '/rest/v1/rpc/waytty_sync_get',
        '/rest/v1/rpc/waytty_sync_delete',
      ]);
      final tokens = <String>{};
      for (final request in requests.skip(1)) {
        expect(request.method, 'POST');
        expect('${request.url} ${request.body}', isNot(contains(code)));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final token = body['access_token'] as String;
        expect(token, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(
          body.keys,
          everyElement(isIn(['access_token', 'encrypted_payload'])),
        );
        tokens.add(token);
      }
      expect(tokens, hasLength(1));
      expect(
        await SupabaseService.deriveAccessToken('DIFFERENT2345'),
        isNot(tokens.single),
      );
    },
  );

  test('an absent encrypted workspace returns null', () async {
    final client = SupabaseClient(
      'https://fixture.invalid',
      'fixture-anon',
      httpClient: MockClient(
        (request) async => http.Response(
          'null',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    addTearDown(client.dispose);
    final service = SupabaseService('', '', 'ABCD2345EFGH', client: client);
    expect(await service.fetchPayload(), isNull);
    expect(await service.fetchUpdatedAt(), isNull);
  });
}

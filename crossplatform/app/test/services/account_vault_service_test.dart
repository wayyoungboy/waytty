import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yourssh/services/account_vault_service.dart';

const config = AccountCloudConfig(url: 'https://fixture.invalid');
final token = 'a' * 43;
final registration = 'b' * 43;
Map<String, dynamic> get session => {
  'access_token': token,
  'user': {'id': 'fixture-user', 'email': 'fixture@example.com'},
};
http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('requires HTTPS without embedded credentials, query or fragment', () {
    for (final url in [
      '',
      'http://api.example.com',
      'https://user:pass@api.example.com',
      'https://api.example.com?token=secret',
      'https://api.example.com#fragment',
    ]) {
      expect(AccountCloudConfig(url: url).isConfigured, false);
    }
    expect(config.isConfigured, true);
  });

  test(
    'standalone API verifies before vault access, keeps passwords out of vault requests and revokes sessions',
    () async {
      final requests = <http.Request>[];
      final service = HttpAccountVaultService(
        config,
        client: MockClient((request) async {
          requests.add(request);
          expect(request.followRedirects, false);
          return jsonResponse(switch (request.url.path) {
            '/v1/auth/signup' => {
              'verification_required': true,
              'registration_token': registration,
            },
            '/v1/auth/resend' => {'verification_required': true},
            '/v1/auth/verify' => session,
            '/v1/auth/logout' => {'ok': true},
            '/v1/vault' =>
              request.method == 'GET'
                  ? {
                      'vault': {
                        'encrypted_payload': 'ciphertext',
                        'revision': 2,
                      },
                    }
                  : {'revision': 3},
            _ => throw StateError('Unexpected route'),
          });
        }),
      );
      expect(
        await service.signUp('fixture@example.com', 'login-pass-123'),
        false,
      );
      await expectLater(service.fetch(), throwsA(isA<AccountCloudException>()));
      await service.resendVerification('fixture@example.com');
      await service.verifyEmail('fixture@example.com', '123456');
      expect(service.email, 'fixture@example.com');
      expect((await service.fetch())!.revision, 2);
      expect(await service.save('ciphertext', 2), 3);
      expect(jsonDecode(requests[2].body), {
        'email': 'fixture@example.com',
        'code': '123456',
        'registration_token': registration,
      });
      expect(jsonDecode(requests.last.body), {
        'encrypted_payload': 'ciphertext',
        'expected_revision': 2,
      });
      for (final request in requests.where((r) => r.url.path == '/v1/vault')) {
        expect(request.headers['authorization'], 'Bearer $token');
        expect(request.body, isNot(contains('login-pass-123')));
        expect(request.body, isNot(contains('123456')));
        expect(request.headers.containsKey('apikey'), false);
      }
      await service.dispose();
      expect(service.userId, isNull);
      expect(requests.last.url.path, '/v1/auth/logout');
    },
  );

  test(
    'expired session clears identity and conflicts keep protocol error',
    () async {
      var status = 409;
      final service = HttpAccountVaultService(
        config,
        client: MockClient((request) async {
          if (request.url.path == '/v1/auth/login') {
            return jsonResponse(session);
          }
          return jsonResponse({
            'error': {
              'code': status == 409 ? 'revision_conflict' : 'unauthorized',
            },
          }, status);
        }),
      );
      addTearDown(service.dispose);
      await service.signIn('fixture@example.com', 'login-pass-123');
      await expectLater(
        service.save('ciphertext', 0),
        throwsA(
          isA<AccountCloudException>().having(
            (e) => e.code,
            'code',
            'revision_conflict',
          ),
        ),
      );
      expect(service.userId, isNotNull);
      status = 401;
      await expectLater(service.fetch(), throwsA(isA<AccountCloudException>()));
      expect(service.userId, isNull);
    },
  );

  test(
    'restarts registration challenge when an unverified account logs in after app restart',
    () async {
      final paths = <String>[];
      final service = HttpAccountVaultService(
        config,
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/v1/auth/login') {
            return jsonResponse({
              'error': {'code': 'email_not_confirmed'},
            }, 403);
          }
          if (request.url.path == '/v1/auth/signup') {
            return jsonResponse({
              'verification_required': true,
              'registration_token': registration,
            }, 202);
          }
          return jsonResponse(session);
        }),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.signIn('fixture@example.com', 'login-pass-123'),
        throwsA(
          isA<AccountCloudException>().having(
            (e) => e.code,
            'code',
            'email_not_confirmed',
          ),
        ),
      );
      expect(paths, ['/v1/auth/login', '/v1/auth/signup']);
      await service.verifyEmail('fixture@example.com', '123456');
      expect(service.userId, 'fixture-user');
    },
  );

  test('late sign-in response cannot restore a disposed session', () async {
    final gate = Completer<http.Response>();
    final service = HttpAccountVaultService(
      config,
      client: MockClient((_) => gate.future),
    );
    final signingIn = service.signIn('fixture@example.com', 'login-pass-123');
    final checked = expectLater(
      signingIn,
      throwsA(isA<AccountCloudException>()),
    );
    await service.dispose();
    gate.complete(jsonResponse(session));
    await checked;
    expect(service.userId, isNull);
  });
}

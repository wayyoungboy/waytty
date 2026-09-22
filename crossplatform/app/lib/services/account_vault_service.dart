import 'dart:convert';

import 'package:http/http.dart' as http;

class AccountVaultRecord {
  final String ciphertext;
  final int revision;
  AccountVaultRecord(this.ciphertext, this.revision);
}

/// The standalone WayTTY API. No database credentials belong in a client build.
class AccountCloudConfig {
  final String url;
  const AccountCloudConfig({
    this.url = const String.fromEnvironment('WAYTTY_CLOUD_URL'),
  });

  bool get isConfigured {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }
}

class AccountCloudException implements Exception {
  final int status;
  final String code;
  const AccountCloudException(this.status, this.code);
  @override
  String toString() => 'AccountCloudException($status, $code)';
}

abstract class AccountVaultBackend {
  String? get userId;
  String? get email;
  Future<bool> signUp(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> verifyEmail(String email, String code);
  Future<void> resendVerification(String email);
  Future<AccountVaultRecord?> fetch();
  Future<int> save(String ciphertext, int expectedRevision);
  Future<void> dispose();
}

/// Sessions and registration tokens live only in memory. Every vault request
/// uses an opaque Bearer token; the API derives ownership from that session.
class HttpAccountVaultService implements AccountVaultBackend {
  final http.Client _client;
  final Uri _base;
  bool _disposed = false;
  String? _token;
  String? _id;
  String? _email;
  String? _registrationToken;
  String? _pendingEmail;

  HttpAccountVaultService(AccountCloudConfig config, {http.Client? client})
    : _base = Uri.parse(config.url),
      _client = client ?? http.Client() {
    if (!config.isConfigured) {
      throw ArgumentError('An HTTPS cloud URL is required');
    }
  }

  @override
  String? get userId => _id;
  @override
  String? get email => _email;

  void _clearSession() {
    _token = null;
    _id = null;
    _email = null;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    if (_disposed) throw const AccountCloudException(0, 'disconnected');
    if (authenticated && _token == null) {
      throw const AccountCloudException(401, 'unauthorized');
    }
    final uri = _base.replace(
      path: '${_base.path.replaceFirst(RegExp(r'/$'), '')}$path',
    );
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers['accept'] = 'application/json';
    if (authenticated) request.headers['authorization'] = 'Bearer $_token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      if (bytes.length + chunk.length > 16 * 1024 * 1024 + 4096) {
        throw const AccountCloudException(0, 'invalid_response');
      }
      bytes.addAll(chunk);
    }
    if (_disposed) throw const AccountCloudException(0, 'disconnected');
    Map<String, dynamic> result;
    try {
      result = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const AccountCloudException(0, 'invalid_response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (authenticated && response.statusCode == 401) _clearSession();
      final error = result['error'];
      // Preserve only protocol error identifiers, never server exception text.
      final code = error is Map ? error['code'] : null;
      throw AccountCloudException(
        response.statusCode,
        code is String && RegExp(r'^[a-z_]{1,64}$').hasMatch(code)
            ? code
            : 'request_failed',
      );
    }
    return result;
  }

  void _acceptSession(Map<String, dynamic> result) {
    if (_disposed) throw const AccountCloudException(0, 'disconnected');
    final token = result['access_token'];
    final user = result['user'];
    if (token is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ||
        user is! Map ||
        user['id'] is! String ||
        user['email'] is! String) {
      throw const AccountCloudException(0, 'invalid_response');
    }
    _token = token;
    _id = user['id'] as String;
    _email = user['email'] as String;
    _registrationToken = null;
    _pendingEmail = null;
  }

  @override
  Future<bool> signUp(String email, String password) async {
    _clearSession();
    final result = await _request(
      'POST',
      '/v1/auth/signup',
      body: {'email': email, 'password': password},
    );
    final registration = result['registration_token'];
    if (result['verification_required'] != true ||
        registration is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(registration)) {
      throw const AccountCloudException(0, 'invalid_response');
    }
    _registrationToken = registration;
    _pendingEmail = email;
    return false;
  }

  @override
  Future<void> signIn(String email, String password) async {
    _clearSession();
    try {
      _acceptSession(
        await _request(
          'POST',
          '/v1/auth/login',
          body: {'email': email, 'password': password},
        ),
      );
    } on AccountCloudException catch (error) {
      if (error.code == 'email_not_confirmed') {
        // After an app restart the previous registration token is unavailable.
        // Start a fresh challenge bound to this password before asking for OTP.
        if (_registrationToken == null || _pendingEmail != email) {
          await signUp(email, password);
        }
      }
      rethrow;
    }
  }

  Map<String, dynamic> _verification(String email) {
    if (_registrationToken == null || email != _pendingEmail) {
      throw const AccountCloudException(400, 'verification_failed');
    }
    return {'email': email, 'registration_token': _registrationToken};
  }

  @override
  Future<void> verifyEmail(String email, String code) async {
    _acceptSession(
      await _request(
        'POST',
        '/v1/auth/verify',
        body: {..._verification(email), 'code': code},
      ),
    );
  }

  @override
  Future<void> resendVerification(String email) async {
    await _request('POST', '/v1/auth/resend', body: _verification(email));
  }

  @override
  Future<AccountVaultRecord?> fetch() async {
    final result = await _request('GET', '/v1/vault', authenticated: true);
    if (!result.containsKey('vault')) {
      throw const AccountCloudException(0, 'invalid_response');
    }
    final vault = result['vault'];
    if (vault == null) return null;
    if (vault is! Map ||
        vault['encrypted_payload'] is! String ||
        vault['revision'] is! int ||
        (vault['revision'] as int) < 1) {
      throw const AccountCloudException(0, 'invalid_response');
    }
    return AccountVaultRecord(
      vault['encrypted_payload'] as String,
      vault['revision'] as int,
    );
  }

  @override
  Future<int> save(String ciphertext, int expectedRevision) async {
    final result = await _request(
      'PUT',
      '/v1/vault',
      authenticated: true,
      body: {
        'encrypted_payload': ciphertext,
        'expected_revision': expectedRevision,
      },
    );
    if (result['revision'] != expectedRevision + 1) {
      throw const AccountCloudException(0, 'invalid_response');
    }
    return result['revision'] as int;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    final token = _token;
    _disposed = true;
    _clearSession();
    _registrationToken = null;
    _pendingEmail = null;
    try {
      if (token != null) {
        final uri = _base.replace(
          path: '${_base.path.replaceFirst(RegExp(r'/$'), '')}/v1/auth/logout',
        );
        final request = http.Request('POST', uri)..followRedirects = false;
        request.headers['authorization'] = 'Bearer $token';
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 5));
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // Local sign-out always completes; unreachable sessions expire server-side.
    } finally {
      _client.close();
    }
  }
}

import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_credentials.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final calls = <String>[];
  late SshService ssh;
  late bool dialed;
  Host host(AuthType type) => Host(
    label: 'fixture',
    host: '127.0.0.1',
    port: 1,
    username: 'fixture',
    authType: type,
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    dialed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          throw PlatformException(code: 'forbidden-keychain-access');
        });
    ssh = SshService(StorageService());
    ssh.directDialer = (h, p, {timeout}) async {
      dialed = true;
      throw const SocketException('fixture stopped before network');
    };
  });
  tearDown(() {
    expect(calls, isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final auth in AuthType.values) {
    test(
      '$auth without manual input never reads a key file, agent or keychain',
      () async {
        final registered = SshKeyEntry(
          label: 'legacy key',
          algorithm: KeyAlgorithm.ed25519,
          publicKey: '',
          privateKeyPath: 'test/fixtures/keys/id_ed25519',
        );
        await expectLater(
          ssh.connect(host(auth), keyEntry: registered),
          throwsA(isA<ManualAuthenticationRequired>()),
        );
        expect(dialed, isFalse);
      },
    );
  }

  test(
    'manually pasted encrypted private key and passphrase reach the transport',
    () async {
      // Isolated fixture only, never an actual user key file.
      final pem = await File(
        'test/fixtures/keys/id_ed25519_enc',
      ).readAsString();
      ssh.credentialsPrompt = (_, attempt) async =>
          SshCredentials(privateKey: pem, passphrase: 'test-passphrase');
      await expectLater(
        ssh.connect(host(AuthType.privateKey)),
        throwsA(isA<SocketException>()),
      );
      expect(dialed, isTrue);
    },
  );

  test('invalid private key errors never include supplied material', () async {
    const secret = 'private-user-material-do-not-log';
    ssh.credentialsPrompt = (_, attempt) async =>
        const SshCredentials(privateKey: secret);
    await expectLater(
      ssh.connect(host(AuthType.privateKey)),
      throwsA(
        predicate(
          (e) => e is FormatException && !e.toString().contains(secret),
        ),
      ),
    );
    expect(dialed, isFalse);
  });

  test(
    'parallel connects share one prompt and cancellation clears the pending request',
    () async {
      final input = Completer<SshCredentials?>();
      var prompts = 0;
      ssh.credentialsPrompt = (_, attempt) {
        prompts++;
        return input.future;
      };
      final target = host(AuthType.password);
      final first = expectLater(
        ssh.connect(target),
        throwsA(isA<AuthenticationCancelled>()),
      );
      final second = expectLater(
        ssh.connect(target),
        throwsA(isA<AuthenticationCancelled>()),
      );
      expect(prompts, 1);
      input.complete(null);
      await Future.wait([first, second]);
      expect(dialed, isFalse);
      await expectLater(
        ssh.connect(target),
        throwsA(isA<AuthenticationCancelled>()),
      );
      expect(prompts, 2, reason: 'A new manual attempt may prompt again');
    },
  );

  test(
    'cancelled input causes no connection and no automatic re-prompt',
    () async {
      var prompts = 0;
      ssh.credentialsPrompt = (_, attempt) async {
        prompts++;
        return null;
      };
      final sessions = SessionProvider(ssh, TabMetadataService())
        ..autoReconnectEnabled = () => true;
      await sessions.connect(host(AuthType.password));
      expect(sessions.sshSessions.single.errorMessage, contains('cancelled'));
      expect(sessions.sshSessions.single.reconnectCount, 0);
      expect(prompts, 1);
      expect(dialed, isFalse);
      sessions.dispose();
    },
  );

  test('jump host requires its own manual input', () async {
    Host? requested;
    final jump = host(AuthType.password);
    ssh.credentialsPrompt = (h, attempt) async {
      requested = h;
      return null;
    };
    await expectLater(
      ssh.dialHop(jump, null),
      throwsA(isA<AuthenticationCancelled>()),
    );
    expect(requested, same(jump));
    expect(dialed, isFalse);
  });

  test(
    'connection test uses the entered password without a stored fallback',
    () async {
      final result = await ssh.testConnection(
        host(AuthType.password),
        password: 'fixture',
      );
      expect(result.success, isFalse);
      expect(result.error, 'Host unreachable');
      expect(dialed, isTrue);
    },
  );

  test(
    'background SFTP, exec and tunnel acquisition do not prompt or connect',
    () async {
      var prompts = 0;
      ssh.credentialsPrompt = (_, attempt) async {
        prompts++;
        return const SshCredentials(password: 'fixture');
      };
      final h = host(AuthType.password);
      ssh.defaultHostKeyVerifier = (_, _, _, _, {attempt}) async => true;
      await expectLater(ssh.ensureClient(h), throwsStateError);
      await expectLater(ssh.openSftp(h), throwsStateError);
      await expectLater(ssh.exec(h, 'fixture'), throwsStateError);
      expect(prompts, 0);
      expect(dialed, isFalse);
    },
  );
}

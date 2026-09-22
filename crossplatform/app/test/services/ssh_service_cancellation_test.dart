import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/proxy_settings.dart';
import 'package:yourssh/models/ssh_connection_attempt.dart';
import 'package:yourssh/models/ssh_credentials.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

class _Socket implements SSHSocket {
  bool destroyed = false;
  @override
  void destroy() => destroyed = true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Host target(String id) =>
    Host(id: id, label: id, host: 'fixture.invalid', username: 'fixture');
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SshService ssh;
  late int dials;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dials = 0;
    ssh = SshService(StorageService())
      ..directDialer = (_, _, {timeout}) async {
        dials++;
        throw const SocketException('fixture stops before networking');
      };
  });

  test(
    'disconnect rejects pending input immediately and ignores its late answer',
    () async {
      final input = Completer<SshCredentials?>();
      SshConnectionAttempt? scope;
      ssh.credentialsPrompt = (_, attempt) {
        scope = attempt;
        return input.future;
      };
      final host = target('cancel');
      final cancelled = expectLater(
        ssh.connect(host),
        throwsA(isA<AuthenticationCancelled>()),
      );
      ssh.disconnect(host.id);
      await cancelled;
      expect(scope!.isCancelled, true);
      // Start a new attempt before the old prompt answers; old cleanup must not cancel it.
      final replacement = Completer<SshCredentials?>();
      ssh.credentialsPrompt = (_, _) => replacement.future;
      final retry = expectLater(
        ssh.connect(host),
        throwsA(isA<SocketException>()),
      );
      input.complete(const SshCredentials(password: 'discarded-fixture'));
      await flush();
      expect(dials, 0);
      replacement.complete(const SshCredentials(password: 'new-fixture'));
      await retry;
      expect(dials, 1);
      expect(ssh.isConnected(host.id), false);
    },
  );

  test(
    'disconnect cancels a connectivity test waiting for credentials',
    () async {
      final input = Completer<SshCredentials?>();
      ssh.credentialsPrompt = (_, _) => input.future;
      final host = target('test');
      final pending = ssh.testConnection(host);
      ssh.disconnect(host.id);
      expect((await pending).success, false);
      input.complete(const SshCredentials(password: 'late'));
      await flush();
      expect(dials, 0);
    },
  );

  test('disconnect closes a transport returned after cancellation', () async {
    final transport = Completer<SSHSocket>();
    final started = Completer<void>();
    ssh.credentialsPrompt = (_, _) async =>
        const SshCredentials(password: 'fixture');
    ssh.directDialer = (_, _, {timeout}) {
      started.complete();
      return transport.future;
    };
    final host = target('socket');
    final pending = expectLater(
      ssh.connect(host),
      throwsA(isA<AuthenticationCancelled>()),
    );
    await started.future;
    ssh.disconnect(host.id);
    await pending;
    final socket = _Socket();
    transport.complete(socket);
    await flush();
    expect(socket.destroyed, true);
    expect(ssh.isConnected(host.id), false);
  });

  test('disconnect during proxy input never dials the proxy', () async {
    final prompt = Completer<String?>();
    final started = Completer<void>();
    final host = target('proxy')
      ..proxyType = ProxyType.socks5
      ..proxyHost = 'proxy.invalid'
      ..proxyPort = 1080
      ..proxyUsername = 'fixture';
    ssh.credentialsPrompt = (_, _) async =>
        const SshCredentials(password: 'fixture');
    ssh.proxyPasswordPrompt = (_, _) {
      started.complete();
      return prompt.future;
    };
    ssh.proxyDialer =
        ({
          required settings,
          required targetHost,
          required targetPort,
          timeout,
        }) async {
          dials++;
          throw const SocketException('must not dial');
        };
    final pending = expectLater(
      ssh.connect(host),
      throwsA(isA<AuthenticationCancelled>()),
    );
    await started.future;
    ssh.disconnect(host.id);
    await pending;
    prompt.complete('late-proxy-fixture');
    await flush();
    expect(dials, 0);
  });

  test(
    'shared in-flight hop survives one cancellation; last target cancels it',
    () async {
      final hopInput = Completer<SshCredentials?>();
      final hopStarted = Completer<void>();
      SshConnectionAttempt? hopScope;
      final hop = target('jump');
      ssh.credentialsPrompt = (h, scope) async {
        if (h.id != hop.id) return const SshCredentials(password: 'fixture');
        hopScope = scope;
        if (!hopStarted.isCompleted) hopStarted.complete();
        return hopInput.future;
      };
      final chain = [(host: hop, keyEntry: null)];
      final a = target('a');
      final b = target('b');
      final first = expectLater(
        ssh.connect(a, jumpChain: chain),
        throwsA(isA<AuthenticationCancelled>()),
      );
      await hopStarted.future;
      final second = expectLater(
        ssh.connect(b, jumpChain: chain),
        throwsA(isA<AuthenticationCancelled>()),
      );
      await flush();
      ssh.disconnect(a.id);
      await first;
      expect(hopScope!.isCancelled, false);
      ssh.disconnect(b.id);
      await second;
      expect(hopScope!.isCancelled, true);
      hopInput.complete(const SshCredentials(password: 'late-hop-fixture'));
      await flush();
      expect(dials, 0);
    },
  );
}

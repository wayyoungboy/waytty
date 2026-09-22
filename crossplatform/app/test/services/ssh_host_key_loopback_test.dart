import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_credentials.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final python = Platform.environment['WAYTTY_SSH_FIXTURE_PYTHON'];
  test(
    'real SSH verifies target and jump keys before authentication, including tests',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('waytty-host-key-');
      final evidence = File('${root.path}/auth-count');
      final server = await Process.start(python!, [
        'test/fixtures/ssh_server.py',
        root.path,
        evidence.path,
      ]);
      final stderr = StringBuffer();
      server.stderr.transform(utf8.decoder).listen(stderr.write);
      final ssh = SshService(StorageService())
        ..credentialsPrompt = (_, _) async =>
            const SshCredentials(password: 'fixture-only-password');
      final hosts = <Host>[];
      try {
        final line = await server.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 10));
        final port = jsonDecode(line)['port'] as int;
        Host host(String id) {
          final h = Host(
            id: id,
            label: id,
            host: '127.0.0.1',
            port: port,
            username: 'fixture',
          );
          hosts.add(h);
          return h;
        }

        int authStarts() =>
            evidence.existsSync() ? evidence.readAsLinesSync().length : 0;
        var checks = 0;
        // With no verifier, fail closed for both ordinary and test connections.
        expect((await ssh.testConnection(host('no-verifier'))).success, false);
        await expectLater(
          ssh.connect(host('connect-no-verifier')),
          throwsA(isA<SSHAuthAbortError>()),
        );
        expect(authStarts(), 0);
        ssh.defaultHostKeyVerifier = (h, p, type, fp, {attempt}) async {
          expect(h, '127.0.0.1');
          expect(p, port);
          expect(type, 'ssh-ed25519');
          expect(fp, isNotEmpty);
          checks++;
          return false;
        };
        expect(
          (await ssh.testConnection(host('rejected-target'))).success,
          false,
        );
        expect(checks, 1);
        expect(authStarts(), 0);
        final jump = host('jump');
        expect(
          (await ssh.testConnection(
            host('rejected-jump'),
            jumpChain: [(host: jump, keyEntry: null)],
          )).success,
          false,
        );
        expect(checks, 2);
        expect(
          authStarts(),
          0,
          reason: 'Rejected hop keys must stop before password auth',
        );

        checks = 0;
        ssh.defaultHostKeyVerifier = (_, _, _, _, {attempt}) async =>
            ++checks == 1;
        expect(
          (await ssh.testConnection(
            host('target-rejected-after-hop'),
            jumpChain: [(host: jump, keyEntry: null)],
          )).success,
          false,
        );
        expect(checks, 2);
        expect(authStarts(), 1, reason: 'Only the accepted hop authenticates');

        ssh.defaultHostKeyVerifier = (_, _, _, _, {attempt}) async {
          checks++;
          return true;
        };
        expect(
          (await ssh.testConnection(
            host('accepted'),
            jumpChain: [(host: jump, keyEntry: null)],
          )).success,
          true,
        );
        expect(checks, 4);
        expect(authStarts(), 3);

        final waiting = Completer<void>();
        final verdict = Completer<bool>();
        ssh.defaultHostKeyVerifier = (_, _, _, _, {attempt}) {
          waiting.complete();
          return verdict.future;
        };
        final cancelled = host('cancel-verification');
        final connecting = expectLater(
          ssh.connect(cancelled),
          throwsA(isA<AuthenticationCancelled>()),
        );
        await waiting.future;
        ssh.disconnect(cancelled.id);
        await connecting;
        verdict.complete(true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          authStarts(),
          3,
          reason: 'A late trust answer cannot authenticate a cancelled attempt',
        );
        expect(ssh.isConnected(cancelled.id), false);

        // A shared in-flight hop belongs to all its targets, not just the
        // session which first opened its manual authentication prompt.
        ssh.defaultHostKeyVerifier = (_, _, _, _, {attempt}) async => true;
        final hopInput = Completer<SshCredentials?>();
        final hopPrompted = Completer<void>();
        final survivorPrompted = Completer<void>();
        final sharedHop = host('shared-hop');
        final removed = host('removed-target');
        final survivor = host('surviving-target');
        var hopPrompts = 0;
        ssh.credentialsPrompt = (h, _) async {
          if (h.id == sharedHop.id) {
            hopPrompts++;
            hopPrompted.complete();
            return hopInput.future;
          }
          if (h.id == survivor.id) survivorPrompted.complete();
          return const SshCredentials(password: 'fixture-only-password');
        };
        final chain = [(host: sharedHop, keyEntry: null)];
        final first = expectLater(
          ssh.connect(removed, jumpChain: chain),
          throwsA(isA<AuthenticationCancelled>()),
        );
        await hopPrompted.future;
        final second = ssh.connect(survivor, jumpChain: chain);
        await survivorPrompted.future;
        await Future<void>.delayed(Duration.zero);
        ssh.disconnect(removed.id);
        await first;
        hopInput.complete(
          const SshCredentials(password: 'fixture-only-password'),
        );
        expect((await second).isClosed, false);
        expect(hopPrompts, 1);
        expect(ssh.isConnected(removed.id), false);
        expect(
          authStarts(),
          5,
          reason: 'Only the shared hop and surviving target authenticate',
        );

        final pins = KnownHostsProvider.forTest([]);
        addTearDown(pins.dispose);
        ssh.defaultHostKeyVerifier = pins.verifyHostKey;
        Future<void> challengeReady() {
          final ready = Completer<void>();
          void check() {
            if (pins.pendingChallenge != null && !ready.isCompleted) {
              ready.complete();
            }
          }

          pins.addListener(check);
          check();
          return ready.future.whenComplete(() => pins.removeListener(check));
        }

        final firstSeen = host('first-trust');
        var completed = false;
        final firstTest = ssh.testConnection(firstSeen).then((result) {
          completed = true;
          return result;
        });
        await challengeReady();
        expect(pins.hosts, isEmpty);
        expect(authStarts(), 5);
        // Human review must not be cut off by the 10-second network timeout.
        await Future<void>.delayed(const Duration(seconds: 11));
        expect(completed, false);
        pins.pendingChallenge!.resolve(true);
        expect((await firstTest).success, true);
        expect(pins.hosts.length, 1);
        expect(authStarts(), 6);
        expect((await ssh.testConnection(firstSeen)).success, true);
        expect(pins.pendingChallenge, isNull);
        expect(authStarts(), 7);

        await pins.remove(pins.hosts.single);
        final cancelledTrust = host('cancel-first-trust');
        final checking = ssh.testConnection(cancelledTrust);
        await challengeReady();
        ssh.disconnect(cancelledTrust.id);
        expect((await checking).success, false);
        expect(pins.hosts, isEmpty);
        expect(pins.pendingChallenge, isNull);
        expect(authStarts(), 7);

        SSHSocket? interruptedSocket;
        final dial = ssh.directDialer;
        ssh.directDialer = (h, p, {timeout}) async =>
            interruptedSocket = await dial(h, p, timeout: timeout);
        final interrupted = expectLater(ssh.connect(host('network-dropped')),
            throwsA(isA<SSHAuthAbortError>()));
        await challengeReady();
        interruptedSocket!.destroy();
        await interrupted;
        expect(pins.pendingChallenge, isNull);
        expect(pins.hosts, isEmpty);
        expect(authStarts(), 7);
      } finally {
        for (final host in hosts) {
          ssh.disconnect(host.id);
        }
        server.stdin.writeln();
        await server.stdin.close();
        await server.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            server.kill();
            return -1;
          },
        );
        await root.delete(recursive: true);
      }
    },
    skip: python == null
        ? 'Set WAYTTY_SSH_FIXTURE_PYTHON to isolated asyncssh Python'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

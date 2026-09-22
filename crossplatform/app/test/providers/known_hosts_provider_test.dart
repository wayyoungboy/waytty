import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/known_host.dart';
import 'package:yourssh/models/ssh_connection_attempt.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';

// Build a Uint8List from a colon-hex string like 'aa:bb:cc'
Uint8List _fp(String hex) {
  final octets = hex.split(':');
  return Uint8List.fromList(octets.map((h) => int.parse(h, radix: 16)).toList());
}

KnownHost _entry(String host, String fp) => KnownHost(
      host: host,
      port: 22,
      keyType: 'ecdsa-sha2-nistp256',
      fingerprint: fp,
      addedAt: DateTime(2026),
    );

void main() {
  const host = 'server.example.com';
  const port = 22;
  const keyType = 'ecdsa-sha2-nistp256';

  group('verifyHostKey', () {
    test('unknown host is saved only after explicit trust', () async {
      final provider = KnownHostsProvider.forTest([]);
      final future = provider.verifyHostKey(host, port, keyType, _fp('aa:bb:cc'));
      expect(provider.hosts, isEmpty);
      expect(provider.pendingChallenge!.isMismatch, false);
      provider.pendingChallenge!.resolve(true);
      expect(await future, true);
      expect(provider.hosts.length, 1);
      expect(provider.hosts.first.fingerprint, 'aa:bb:cc');
    });

    test('rejecting or cancelling first trust saves no pin', () async {
      final provider = KnownHostsProvider.forTest([]);
      var pending = provider.verifyHostKey(host, port, keyType, _fp('aa:bb:cc'));
      provider.pendingChallenge!.reject();
      expect(await pending, false);
      expect(provider.hosts, isEmpty);
      final attempt = SshConnectionAttempt();
      pending = provider.verifyHostKey(host, port, keyType, _fp('aa:bb:cc'), attempt: attempt);
      final challenge = provider.pendingChallenge!;
      attempt.cancel();
      challenge.resolve(true); // late UI answer cannot persist a cancelled pin
      expect(await pending, false);
      expect(provider.hosts, isEmpty);
      expect(provider.pendingChallenge, isNull);
      provider.dispose();
    });

    test('parallel requests queue; a later different key is shown as a mismatch', () async {
      final provider = KnownHostsProvider.forTest([]);
      final first = provider.verifyHostKey(host, port, keyType, _fp('aa:bb:cc'));
      final second = provider.verifyHostKey(host, port, keyType, _fp('dd:ee:ff'));
      expect(provider.pendingChallenge!.newFingerprint, 'aa:bb:cc');
      provider.pendingChallenge!.resolve(true);
      expect(await first, true);
      expect(provider.pendingChallenge!.isMismatch, true);
      expect(provider.pendingChallenge!.oldFingerprint, 'aa:bb:cc');
      provider.pendingChallenge!.reject();
      expect(await second, false);
      expect(provider.hosts.single.fingerprint, 'aa:bb:cc');
      provider.dispose();
    });

    test('disposing with pending prompts rejects them without saving', () async {
      final provider = KnownHostsProvider.forTest([]);
      final future = provider.verifyHostKey(host, port, keyType, _fp('aa:bb:cc'));
      provider.dispose();
      expect(await future, false);
      expect(provider.hosts, isEmpty);
    });

    test('known host with matching fingerprint is trusted', () async {
      final provider = KnownHostsProvider.forTest([_entry(host, 'aa:bb:cc')]);
      final result = await provider.verifyHostKey(host, port, keyType, _fp('aa:bb:cc'));
      expect(result, true);
      expect(provider.hosts.length, 1);
    });

    test('mismatched key creates pendingChallenge with correct fingerprints', () async {
      final provider = KnownHostsProvider.forTest([_entry(host, 'aa:bb:cc')]);
      final future = provider.verifyHostKey(host, port, keyType, _fp('dd:ee:ff'));
      expect(provider.pendingChallenge, isNotNull);
      expect(provider.pendingChallenge!.oldFingerprint, 'aa:bb:cc');
      expect(provider.pendingChallenge!.newFingerprint, 'dd:ee:ff');
      provider.pendingChallenge!.resolve(false);
      expect(await future, false);
      expect(provider.pendingChallenge, isNull);
    });

    test('trusting mismatch replaces stored fingerprint', () async {
      final provider = KnownHostsProvider.forTest([_entry(host, 'aa:bb:cc')]);
      final future = provider.verifyHostKey(host, port, keyType, _fp('dd:ee:ff'));
      provider.pendingChallenge!.resolve(true);
      final result = await future;
      expect(result, true);
      expect(provider.hosts.length, 1);
      expect(provider.hosts.first.fingerprint, 'dd:ee:ff');
    });
  });

  group('remove', () {
    test('removes matching entry', () async {
      final provider = KnownHostsProvider.forTest([_entry(host, 'aa:bb:cc')]);
      await provider.remove(provider.hosts.first);
      expect(provider.hosts, isEmpty);
    });
  });
}

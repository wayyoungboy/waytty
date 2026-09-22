import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/ssh_credentials.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/agent_forwarding_handler.dart';

void main() {
  test(
    'legacy forwarding rejects every request without invoking credential callbacks',
    () async {
      var calls = 0;
      final handler = AgentForwardingHandler(
        connectSystemAgent: () async {
          calls++;
          throw StateError('forbidden');
        },
        loadKeychainIdentities: () async {
          calls++;
          throw StateError('forbidden');
        },
        onRequestServed: (_) => calls++,
      );
      for (final type in [11, 13, 17]) {
        expect(await handler.handleRequest(Uint8List.fromList([type])), [5]);
      }
      expect(calls, 0);
    },
  );
  test(
    'legacy private-key loaders refuse without file IO or passphrase reads',
    () async {
      await IOOverrides.runZoned(() async {
        await expectLater(
          loadKeyPairsFromFile('fixture', null),
          throwsA(isA<ManualAuthenticationRequired>()),
        );
        var passphraseReads = 0;
        await expectLater(
          loadKeychainKeyPairs(
            [
              SshKeyEntry(
                label: 'legacy',
                algorithm: KeyAlgorithm.ed25519,
                publicKey: '',
                privateKeyPath: 'fixture',
              ),
            ],
            (_) async {
              passphraseReads++;
              return null;
            },
          ),
          throwsA(isA<ManualAuthenticationRequired>()),
        );
        expect(passphraseReads, 0);
      }, createFile: (_) => throw StateError('forbidden file access'));
    },
  );
}

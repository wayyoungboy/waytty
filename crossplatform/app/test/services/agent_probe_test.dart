import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/ssh_credentials.dart';
import 'package:yourssh/services/agent_probe.dart';

void main() {
  test(
    'legacy status probe does not enumerate agent or keychain identities',
    () async {
      var calls = 0;
      final result = await probeAgentStatus(
        listAgentIdentities: () async {
          calls++;
          return [];
        },
        loadKeychainIdentities: () async {
          calls++;
          return [];
        },
      );
      expect(result, isA<AgentProbeNothing>());
      expect(calls, 0);
      await expectLater(
        listSystemAgentIdentities(),
        throwsA(isA<ManualAuthenticationRequired>()),
      );
    },
  );
}

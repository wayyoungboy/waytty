import 'package:dartssh2/dartssh2.dart';

import '../models/ssh_credentials.dart';

/// Legacy display types. Probing is disabled by the manual-auth policy.
sealed class AgentProbeResult {
  const AgentProbeResult();
}

/// System agent reachable; it holds [identityCount] identities.
class AgentProbeSystem extends AgentProbeResult {
  const AgentProbeSystem(this.identityCount);
  final int identityCount;
}

/// No system agent; forwarding would serve [keyCount] app-Keychain keys.
class AgentProbeKeychain extends AgentProbeResult {
  const AgentProbeKeychain(this.keyCount);
  final int keyCount;
}

/// Nothing to serve — no agent and no loadable Keychain keys, or the agent
/// failed mid-probe ([detail] carries the error in that case).
class AgentProbeNothing extends AgentProbeResult {
  const AgentProbeNothing([this.detail]);
  final String? detail;
}

/// Legacy entry point: credential enumeration is forbidden.
Future<List<SSHKeyPair>> listSystemAgentIdentities() async =>
    throw const ManualAuthenticationRequired();

/// No credential callbacks are invoked, even for legacy callers.
Future<AgentProbeResult> probeAgentStatus({
  Future<List<SSHKeyPair>> Function() listAgentIdentities =
      listSystemAgentIdentities,
  required Future<List<SSHKeyPair>> Function() loadKeychainIdentities,
}) async => const AgentProbeNothing('Manual authentication required');

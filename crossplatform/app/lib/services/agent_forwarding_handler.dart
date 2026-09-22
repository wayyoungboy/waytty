import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/ssh_key.dart';
import '../models/ssh_credentials.dart';
import 'system_agent_proxy.dart';

/// Legacy interface retained to reject forwarding without accessing credentials.
class AgentForwardingHandler implements SSHAgentHandler {
  AgentForwardingHandler({
    Future<SystemAgentProxy> Function()? connectSystemAgent,
    required Future<List<SSHKeyPair>> Function() loadKeychainIdentities,
    void Function(bool usedFallback)? onRequestServed,
  });

  @override
  Future<Uint8List> handleRequest(Uint8List request) async =>
      Uint8List.fromList([5]); // SSH_AGENT_FAILURE; do not invoke any loader.
}

/// Automatic file authentication is forbidden, including legacy callers.
Future<List<SSHKeyPair>> loadKeyPairsFromFile(
  String path,
  String? passphrase,
) async => throw const ManualAuthenticationRequired();

/// Never enumerate entries, load passphrases, or open private-key files.
Future<List<SSHKeyPair>> loadKeychainKeyPairs(
  Iterable<SshKeyEntry> entries,
  Future<String?> Function(String keyId) loadPassphrase,
) async => throw const ManualAuthenticationRequired();

import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import '../models/host.dart';
import '../models/ssh_credentials.dart';
import 'certificate_key_pair.dart';

/// Parses only explicitly supplied material. No file, agent or keychain access.
List<SSHKeyPair> parseManualSshIdentity(Host host, SshCredentials input) {
  if (host.authType == AuthType.password) {
    if (input.password == null) throw const ManualAuthenticationRequired();
    return [];
  }
  final pem = input.privateKey;
  if (pem == null || pem.trim().isEmpty) {
    throw const ManualAuthenticationRequired();
  }
  try {
    final pairs = SSHKeyPair.fromPem(
      pem,
      input.passphrase?.isNotEmpty == true ? input.passphrase : null,
    );
    if (pairs.isEmpty) throw const FormatException();
    if (host.authType == AuthType.certificate) {
      final cert = input.certificate?.trim().split(RegExp(r'\s+'));
      if (cert == null || cert.length < 2) throw const FormatException();
      return [CertificateKeyPair(pairs.first, base64.decode(cert[1]))];
    }
    return pairs;
  } catch (_) {
    throw const FormatException(
      'Invalid private key, certificate, or passphrase.',
    );
  }
}

/// Explicit input, or a locally saved key after the user unlocks its store.
/// Only opted-in private-key fields may be encrypted by LocalSshKeyStore.
/// Never logged or populated from files/keychains/SSH agents.
class SshCredentials {
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final String? certificate;
  final bool savePrivateKey;

  const SshCredentials({
    this.password,
    this.privateKey,
    this.passphrase,
    this.certificate,
    this.savePrivateKey = false,
  });

  @override
  String toString() => 'SshCredentials(<redacted>)';
}

class ManualAuthenticationRequired implements Exception {
  const ManualAuthenticationRequired();
  @override
  String toString() => 'Enter credentials manually to connect.';
}

class AuthenticationCancelled implements Exception {
  const AuthenticationCancelled();
  @override
  String toString() => 'Authentication cancelled.';
}

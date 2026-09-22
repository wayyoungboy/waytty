import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// A separate format and domain from legacy sync codes. The vault password
/// never leaves the client; the account ID is authenticated as AES-GCM AAD.
class AccountVaultEncryption {
  static const prefix = 'waytty-vault-v1:';
  static const maxEncodedLength = 16 * 1024 * 1024;
  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  );

  static Future<SecretKey> _key(String password, List<int> salt) =>
      _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  static List<int> _context(String userId) => utf8.encode('$prefix$userId');

  static Future<String> encrypt(
    String plaintext,
    String password,
    String userId,
  ) async {
    if (password.isEmpty || userId.isEmpty) {
      throw const FormatException('Vault password and account are required.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final box = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: await _key(password, salt),
      aad: _context(userId),
    );
    final encoded =
        '$prefix${base64Encode([...salt, ...box.nonce, ...box.cipherText, ...box.mac.bytes])}';
    if (encoded.length > maxEncodedLength) {
      throw const FormatException('The encrypted vault is too large.');
    }
    return encoded;
  }

  static Future<String> decrypt(
    String encoded,
    String password,
    String userId,
  ) async {
    try {
      if (!encoded.startsWith(prefix) ||
          encoded.length > maxEncodedLength ||
          password.isEmpty ||
          userId.isEmpty) {
        throw const FormatException();
      }
      final bytes = base64Decode(encoded.substring(prefix.length));
      if (bytes.length < 44) throw const FormatException();
      final plaintext = await _cipher.decrypt(
        SecretBox(
          bytes.sublist(28, bytes.length - 16),
          nonce: bytes.sublist(16, 28),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: await _key(password, bytes.sublist(0, 16)),
        aad: _context(userId),
      );
      return utf8.decode(plaintext);
    } catch (_) {
      throw const FormatException('Incorrect vault password or damaged data.');
    }
  }
}

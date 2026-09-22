import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/account_vault_encryption.dart';

void main() {
  const password = 'vault-test-123';
  const account = 'account-a';
  test(
    'round trip, random salt/nonce, wrong key and cross-account rejection',
    () async {
      const plaintext = '{"passwords":{"pw_server":"secret-fixture"}}';
      final encrypted = await AccountVaultEncryption.encrypt(
        plaintext,
        password,
        account,
      );
      final second = await AccountVaultEncryption.encrypt(
        plaintext,
        password,
        account,
      );
      expect(encrypted, startsWith(AccountVaultEncryption.prefix));
      expect(encrypted, isNot(second));
      expect(encrypted, isNot(contains('secret-fixture')));
      expect(
        await AccountVaultEncryption.decrypt(encrypted, password, account),
        plaintext,
      );
      await expectLater(
        AccountVaultEncryption.decrypt(encrypted, 'wrong-password', account),
        throwsFormatException,
      );
      await expectLater(
        AccountVaultEncryption.decrypt(encrypted, password, 'account-b'),
        throwsFormatException,
      );
      final bytes = base64Decode(
        encrypted.substring(AccountVaultEncryption.prefix.length),
      );
      bytes[30] ^= 1;
      await expectLater(
        AccountVaultEncryption.decrypt(
          '${AccountVaultEncryption.prefix}${base64Encode(bytes)}',
          password,
          account,
        ),
        throwsFormatException,
      );
    },
  );

  test('rejects legacy, truncated and unsupported ciphertext', () async {
    for (final value in [
      'v1:AAAA',
      'waytty-vault-v2:AAAA',
      'waytty-vault-v1:AAAA',
    ]) {
      await expectLater(
        AccountVaultEncryption.decrypt(value, password, account),
        throwsFormatException,
      );
    }
  });
}

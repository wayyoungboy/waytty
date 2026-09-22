import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

class CertificateKeyPair implements SSHKeyPair {
  final SSHKeyPair _inner;
  final Uint8List _certBytes;

  CertificateKeyPair(this._inner, this._certBytes) {
    if (_certBytes.length < 4) throw FormatException('Cert blob too short');
    final nameLen = ByteData.view(_certBytes.buffer, _certBytes.offsetInBytes, 4)
        .getUint32(0, Endian.big);
    if (_certBytes.length < 4 + nameLen) throw FormatException('Cert blob truncated');
  }

  @override
  String get name => type;

  @override
  String get type {
    final nameLen = ByteData.view(_certBytes.buffer, _certBytes.offsetInBytes, 4)
        .getUint32(0, Endian.big);
    return utf8.decode(_certBytes.sublist(4, 4 + nameLen));
  }

  @override
  SSHHostKey toPublicKey() => _RawBlobHostKey(_certBytes);

  @override
  SSHSignature sign(Uint8List data) => _inner.sign(data);

  @override
  Future<SSHSignature> signAsync(Uint8List data) async => _inner.sign(data);

  @override
  String toPem({String? passphrase}) =>
      throw UnsupportedError('CertificateKeyPair cannot be serialized to PEM');
}

class _RawBlobHostKey implements SSHHostKey {
  final Uint8List _bytes;
  const _RawBlobHostKey(this._bytes);

  @override
  Uint8List encode() => _bytes;
}

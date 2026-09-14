import 'dart:convert';
import 'dart:typed_data';

enum SerialParity { none, odd, even }

enum SerialFlowControl { none, rtsCts, xonXoff }

enum SerialNewline { none, cr, lf, crlf }

enum SerialSignal { dtr, rts, breakSignal }

enum SerialStatus { idle, connecting, connected, disconnected, error, closed }

class SerialException implements Exception {
  const SerialException(this.key, [this.detail]);
  final String key;
  final String? detail;
  @override
  String toString() => detail == null ? key : '$key: $detail';
}

class SerialDeviceInfo {
  const SerialDeviceInfo({
    required this.id,
    required this.path,
    required this.label,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.portIndex = 0,
  });
  final String id, path, label;
  final int? vendorId, productId;
  final String? serialNumber;
  final int portIndex;

  String get description => [
    path,
    if (vendorId != null && productId != null)
      '${vendorId!.toRadixString(16).padLeft(4, '0')}:${productId!.toRadixString(16).padLeft(4, '0')}',
    if (serialNumber?.isNotEmpty == true) serialNumber!,
  ].join(' · ');

  bool matches(SerialDeviceInfo other) =>
      id == other.id &&
      vendorId == other.vendorId &&
      productId == other.productId &&
      serialNumber == other.serialNumber &&
      portIndex == other.portIndex;
}

class SerialConfig {
  const SerialConfig({
    this.baudRate = 115200,
    this.dataBits = 8,
    this.parity = SerialParity.none,
    this.stopBits = 1,
    this.flowControl = SerialFlowControl.none,
  });
  final int baudRate, dataBits, stopBits;
  final SerialParity parity;
  final SerialFlowControl flowControl;

  String get label =>
      '$baudRate · $dataBits${switch (parity) {
        SerialParity.none => 'N',
        SerialParity.odd => 'O',
        SerialParity.even => 'E',
      }}$stopBits';

  void validate() {
    if (baudRate < 1 ||
        baudRate > 4000000 ||
        dataBits < 5 ||
        dataBits > 8 ||
        (stopBits != 1 && stopBits != 2)) {
      throw const FormatException('Invalid serial parameters');
    }
  }

  Map<String, Object> toJson() => {
    'baudRate': baudRate,
    'dataBits': dataBits,
    'parity': parity.name,
    'stopBits': stopBits,
    'flowControl': flowControl.name,
  };

  factory SerialConfig.fromJson(Map<String, dynamic> json) {
    final config = SerialConfig(
      baudRate: json['baudRate'] as int,
      dataBits: json['dataBits'] as int,
      stopBits: json['stopBits'] as int,
      parity: SerialParity.values.byName(json['parity'] as String),
      flowControl: SerialFlowControl.values.byName(
        json['flowControl'] as String,
      ),
    );
    config.validate();
    return config;
  }
}

Uint8List encodeSerialInput(
  String text, {
  bool hex = false,
  SerialNewline newline = SerialNewline.none,
}) {
  final List<int> bytes;
  if (hex) {
    final compact = text.replaceAll(RegExp(r'\s'), '');
    if (compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(compact)) {
      throw const FormatException('Invalid HEX input');
    }
    bytes = [
      for (var i = 0; i < compact.length; i += 2)
        int.parse(compact.substring(i, i + 2), radix: 16),
    ];
  } else {
    bytes = List<int>.of(utf8.encode(text));
  }
  bytes.addAll(switch (newline) {
    SerialNewline.none => <int>[],
    SerialNewline.cr => [13],
    SerialNewline.lf => [10],
    SerialNewline.crlf => [13, 10],
  });
  return Uint8List.fromList(bytes);
}

String serialHex(Iterable<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

class SerialRecord {
  SerialRecord({
    required this.time,
    required this.transmitted,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final DateTime time;
  final bool transmitted;
  final Uint8List bytes;
}

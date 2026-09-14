import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/serial_models.dart';
import 'package:yourssh/models/serial_session.dart';
import 'package:yourssh/services/serial/serial_backend.dart';

class FakeSerialHandle implements SerialHandle {
  final controller = StreamController<Uint8List>.broadcast();
  final writes = <List<int>>[];
  int closes = 0;
  int? maxWrite;
  Object? writeError;
  Completer<int>? pendingWrite;
  @override
  Stream<Uint8List> get input => controller.stream;
  @override
  Future<int> write(Uint8List bytes) async {
    if (writeError != null) throw writeError!;
    final n = pendingWrite != null
        ? await pendingWrite!.future
        : (maxWrite ?? bytes.length).clamp(0, bytes.length);
    writes.add(bytes.take(n).toList());
    return n;
  }

  @override
  Future<void> setSignal(SerialSignal signal, bool enabled) async {}
  @override
  Future<void> close() async {
    closes++;
  }
}

class FakeSerialBackend implements SerialBackend {
  final handle = FakeSerialHandle();
  Completer<SerialHandle>? opening;
  @override
  Future<List<SerialDeviceInfo>> listDevices() async => [device];
  @override
  Future<SerialHandle> open(
    SerialDeviceInfo device,
    SerialConfig config,
  ) async => opening == null ? handle : await opening!.future;
}

const device = SerialDeviceInfo(id: 'test:1', path: 'test:1', label: '调试板');

void main() {
  test('HEX accepts whitespace, preserves NUL and rejects malformed input', () {
    expect(encodeSerialInput('00 ff\nE4 B8 AD', hex: true), [
      0,
      255,
      228,
      184,
      173,
    ]);
    for (final invalid in ['F', 'GG', '0x41', '41,42']) {
      expect(
        () => encodeSerialInput(invalid, hex: true),
        throwsFormatException,
      );
    }
    expect(encodeSerialInput('中文', newline: SerialNewline.crlf), [
      ...utf8.encode('中文'),
      13,
      10,
    ]);
  });

  test('configuration validates and round trips independently from SSH', () {
    const config = SerialConfig(
      baudRate: 9600,
      dataBits: 7,
      parity: SerialParity.even,
      stopBits: 2,
    );
    expect(SerialConfig.fromJson(config.toJson()).toJson(), config.toJson());
    expect(
      () => const SerialConfig(baudRate: 0).validate(),
      throwsFormatException,
    );
    expect(
      () => const SerialConfig(dataBits: 9).validate(),
      throwsFormatException,
    );
  });

  group('serial session', () {
    late FakeSerialBackend backend;
    late SerialSession session;
    setUp(() {
      backend = FakeSerialBackend();
      session = SerialSession(
        device: device,
        config: const SerialConfig(),
        backend: backend,
      );
    });
    tearDown(() async {
      await session.close();
      session.dispose();
      await backend.handle.controller.close();
    });

    test(
      'receives split UTF-8, raw bytes and never sends automatic replies',
      () async {
        await session.connect();
        final data = [...utf8.encode('中文'), 0, 255, 27, 91, 54, 110];
        backend.handle.controller.add(
          Uint8List.fromList(data.take(2).toList()),
        );
        backend.handle.controller.add(
          Uint8List.fromList(data.skip(2).toList()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(session.receivedBytes, data.length);
        expect(session.rawReceived, data);
        expect(session.receivedText, startsWith('中文'));
        expect(backend.handle.writes, isEmpty);
      },
    );

    test('partial writes advance offsets without duplicating bytes', () async {
      backend.handle.maxWrite = 2;
      await session.connect();
      await session.send(Uint8List.fromList([0, 1, 2, 3, 255]));
      expect(backend.handle.writes.expand((b) => b), [0, 1, 2, 3, 255]);
      expect(session.sentBytes, 5);
    });

    test(
      'close during opening closes the late handle without reconnecting',
      () async {
        backend.opening = Completer<SerialHandle>();
        final connecting = session.connect();
        await session.close();
        backend.opening!.complete(backend.handle);
        await connecting;
        expect(session.status, SerialStatus.closed);
        expect(backend.handle.closes, 1);
      },
    );

    test(
      'disconnect cancels pending sends and does not report false success',
      () async {
        await session.connect();
        backend.handle.pendingWrite = Completer<int>();
        final sent = session.send(Uint8List.fromList([1, 2, 3]));
        final assertion = expectLater(sent, throwsA(isA<SerialException>()));
        await session.close();
        backend.handle.pendingWrite!.complete(3);
        await assertion;
        expect(session.status, SerialStatus.closed);
        expect(session.sentBytes, 0);
      },
    );

    test('write error is not retried and marks result unknown', () async {
      await session.connect();
      backend.handle.writeError = StateError('unplugged');
      await expectLater(
        session.send(Uint8List.fromList([1])),
        throwsA(isA<SerialException>()),
      );
      expect(session.status, SerialStatus.error);
      expect(session.errorKey, 'Serial write outcome is unknown');
      expect(session.sentBytes, 0);
    });

    test(
      'stopping a send keeps the connection and does not submit the remainder',
      () async {
        await session.connect();
        backend.handle.pendingWrite = Completer<int>();
        final sent = session.send(Uint8List.fromList([1, 2, 3]));
        final assertion = expectLater(sent, throwsA(isA<SerialException>()));
        session.cancelSend();
        backend.handle.pendingWrite!.complete(1);
        await assertion;
        expect(session.connected, isTrue);
        expect(session.sentBytes, 1);
        expect(backend.handle.writes, [
          [1],
        ]);
      },
    );

    test('stream termination releases handle and prevents new sends', () async {
      await session.connect();
      await backend.handle.controller.close();
      await Future<void>.delayed(Duration.zero);
      expect(session.status, SerialStatus.disconnected);
      expect(backend.handle.closes, 1);
      await expectLater(
        session.send(Uint8List.fromList([1])),
        throwsA(isA<SerialException>()),
      );
    });

    test('bounded RX retains newest bytes and counts discarded data', () async {
      await session.close();
      session.dispose();
      session = SerialSession(
        device: device,
        config: const SerialConfig(),
        backend: backend,
        maxCaptureBytes: 4,
      );
      await session.connect();
      backend.handle.controller.add(Uint8List.fromList([1, 2, 3, 4, 5, 6]));
      await Future<void>.delayed(Duration.zero);
      expect(session.rawReceived, [3, 4, 5, 6]);
      expect(session.discardedBytes, 2);
      expect(session.receivedBytes, 6);
      session.clearCapture();
      expect(session.rawReceived, isEmpty);
      expect(session.receivedBytes, 6);
    });
  });
}

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/serial_models.dart';
import 'package:yourssh/models/serial_session.dart';
import 'package:yourssh/services/serial/android_serial_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('waytty/serial');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'list' => [
          {
            'id': '12:1',
            'path': '/dev/bus/usb/012',
            'label': '开发板',
            'vendorId': 0x10c4,
            'productId': 0xea60,
            'serialNumber': null,
            'portIndex': 1,
          },
        ],
        'open' => 'session-token',
        'write' => (call.arguments['bytes'] as Uint8List).length,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('waytty/serial/events'),
      (_) async => null,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('waytty/serial/events'),
      null,
    );
  });

  test(
    'USB port identity and bytes pass through the native channel unchanged',
    () async {
      final backend = AndroidSerialBackend();
      final device = (await backend.listDevices()).single;
      expect(device.portIndex, 1);
      final handle = await backend.open(
        device,
        const SerialConfig(baudRate: 9600),
      );
      expect(calls.map((c) => c.method), ['list', 'open']);
      final received = <int>[];
      final subscription = handle.input.listen((data) => received.addAll(data));
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.method, 'start');
      final count = await handle.write(Uint8List.fromList([0, 255, 13]));
      expect(count, 3);
      expect(calls.last.arguments['token'], 'session-token');
      expect(calls.last.arguments['bytes'], [0, 255, 13]);
      // Simulate a native RX event and a stray event from a different session.
      for (final token in ['wrong-token', 'session-token']) {
        await messenger.handlePlatformMessage(
          'waytty/serial/events',
          const StandardMethodCodec().encodeSuccessEnvelope({
            'token': token,
            'data': Uint8List.fromList([0, 228, 184, 173]),
          }),
          (_) {},
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(received, [0, 228, 184, 173]);
      await handle.setSignal(SerialSignal.dtr, true);
      expect(calls.last.arguments['signal'], 'dtr');
      await subscription.cancel();
      await handle.close();
      await handle.close();
      expect(calls.where((c) => c.method == 'close').length, 1);
      await expectLater(
        handle.write(Uint8List(1)),
        throwsA(isA<SerialException>()),
      );
    },
  );

  test(
    'native write failures propagate instead of reporting queued bytes as sent',
    () async {
      final backend = AndroidSerialBackend();
      final device = (await backend.listDevices()).single;
      final handle = await backend.open(device, const SerialConfig());
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'write') {
          throw PlatformException(code: 'serial', message: 'USB detached');
        }
        return null;
      });
      await expectLater(
        handle.write(Uint8List(3)),
        throwsA(isA<PlatformException>()),
      );
      await handle.close();
    },
  );

  test(
    'closing during USB permission requests cancels native opening',
    () async {
      final pending = Completer<String>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'open') return pending.future;
        if (call.method == 'cancelOpen') {
          pending.completeError(PlatformException(code: 'cancelled'));
        }
        return null;
      });
      final session = SerialSession(
        device: const SerialDeviceInfo(id: '12:1', path: 'usb', label: 'USB'),
        config: const SerialConfig(),
        backend: AndroidSerialBackend(),
      );
      final opening = session.connect();
      await Future<void>.delayed(Duration.zero);
      await session.close();
      await opening;
      expect(calls.map((c) => c.method), ['open', 'cancelOpen']);
      expect(session.status, SerialStatus.closed);
      session.dispose();
    },
  );
}

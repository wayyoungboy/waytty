import 'dart:async';
import 'package:flutter/services.dart';
import '../../models/serial_models.dart';
import 'serial_backend.dart';

const _channel = MethodChannel('waytty/serial');
const _events = EventChannel('waytty/serial/events');
final _eventStream = _events.receiveBroadcastStream();

class AndroidSerialBackend implements CancellableSerialBackend {
  @override
  Future<void> cancelOpen(SerialDeviceInfo device) =>
      _channel.invokeMethod<void>('cancelOpen', {'id': device.id});
  @override
  Future<List<SerialDeviceInfo>> listDevices() async {
    final items = await _channel.invokeListMethod<dynamic>('list') ?? [];
    return items.map((value) {
      final d = Map<String, dynamic>.from(value as Map);
      return SerialDeviceInfo(
        id: d['id'] as String,
        path: d['path'] as String,
        label: d['label'] as String,
        vendorId: d['vendorId'] as int?,
        productId: d['productId'] as int?,
        serialNumber: d['serialNumber'] as String?,
        portIndex: d['portIndex'] as int,
      );
    }).toList();
  }

  @override
  Future<SerialHandle> open(
    SerialDeviceInfo device,
    SerialConfig config,
  ) async {
    config.validate();
    final handle = _AndroidHandle();
    try {
      final token = await _channel.invokeMethod<String>('open', {
        'id': device.id,
        'vendorId': device.vendorId,
        'productId': device.productId,
        'serialNumber': device.serialNumber,
        ...config.toJson(),
      });
      if (token == null) throw const SerialException('Cannot open serial port');
      handle.token = token;
      // Input starts only after the Dart handle is subscribed, preventing
      // early boot bytes from racing the open response.
      return handle;
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }
}

class _AndroidHandle implements SerialHandle {
  String? token;
  late final StreamController<Uint8List> _input = StreamController<Uint8List>(
    onListen: _listen,
  );
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;
  @override
  Stream<Uint8List> get input => _input.stream;
  void _listen() {
    if (_closed) return;
    _subscription = _eventStream.listen(
      (dynamic event) {
        if (_closed || event is! Map || event['token'] != token) return;
        if (event['data'] is Uint8List) {
          _input.add(event['data'] as Uint8List);
          _channel
              .invokeMethod<void>('ack', {'token': token})
              .catchError((Object _) {});
        }
        if (event['error'] != null) {
          _input.addError(
            SerialException(
              'Serial connection lost',
              event['error'].toString(),
            ),
          );
          unawaited(close());
        }
      },
      onError: (Object error) {
        if (!_closed) _input.addError(error);
        unawaited(close());
      },
    );
    _channel.invokeMethod<void>('start', {'token': token}).catchError((
      Object error,
    ) {
      if (!_closed) _input.addError(error);
      return close();
    });
  }

  @override
  Future<int> write(Uint8List bytes) async {
    if (_closed) throw const SerialException('Serial port is not connected');
    return await _channel.invokeMethod<int>('write', {
          'token': token,
          'bytes': bytes,
        }) ??
        0;
  }

  @override
  Future<void> setSignal(SerialSignal signal, bool enabled) async {
    if (_closed) throw const SerialException('Serial port is not connected');
    await _channel.invokeMethod<void>('signal', {
      'token': token,
      'signal': signal.name,
      'enabled': enabled,
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    try {
      if (token != null) {
        await _channel.invokeMethod<void>('close', {'token': token});
      }
    } finally {
      unawaited(_input.close());
    }
  }
}

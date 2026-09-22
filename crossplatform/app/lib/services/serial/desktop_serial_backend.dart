import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart' as native;
import '../../models/serial_models.dart';
import 'serial_backend.dart';
import 'desktop_serial_config.dart';

/// Each open port is owned by one worker isolate. Native handles never cross
/// isolates, and polling/nonblocking writes do not run on Flutter's UI isolate.
class DesktopSerialBackend implements SerialBackend {
  @override
  Future<List<SerialDeviceInfo>> listDevices() =>
      Isolate.run(_listDesktopDevices);

  @override
  Future<SerialHandle> open(
    SerialDeviceInfo device,
    SerialConfig config,
  ) async {
    config.validate();
    final current = await listDevices();
    if (!current.any(device.matches)) {
      throw const SerialException(
        'Serial device changed; refresh and select again',
      );
    }
    return _DesktopHandle.open(device.path, config);
  }
}

List<SerialDeviceInfo> _listDesktopDevices() {
  final names = native.SerialPort.availablePorts;
  final devices = <SerialDeviceInfo>[];
  for (final name in names) {
    if (Platform.isMacOS &&
        name.startsWith('/dev/tty.') &&
        names.contains(name.replaceFirst('/dev/tty.', '/dev/cu.'))) {
      continue;
    }
    final port = native.SerialPort(name);
    try {
      devices.add(
        SerialDeviceInfo(
          id: name,
          path: name,
          label: port.description ?? port.productName ?? name,
          vendorId: port.vendorId,
          productId: port.productId,
          serialNumber: port.serialNumber,
        ),
      );
    } finally {
      port.dispose();
    }
  }
  devices.sort((a, b) => a.path.compareTo(b.path));
  return devices;
}

class _DesktopHandle implements SerialHandle {
  final _messages = ReceivePort();
  final _input = StreamController<Uint8List>();
  final _ready = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  SendPort? _commands;
  Isolate? _worker;
  StreamSubscription<dynamic>? _subscription;
  int _nextId = 0;
  bool _closed = false;

  static Future<_DesktopHandle> open(String path, SerialConfig config) async {
    final handle = _DesktopHandle();
    handle._subscription = handle._messages.listen(handle._receive);
    try {
      handle._worker = await Isolate.spawn(
        _serialWorker,
        [handle._messages.sendPort, path, config.toJson()],
        onError: handle._messages.sendPort,
        onExit: handle._messages.sendPort,
      );
      await handle._ready.future.timeout(const Duration(seconds: 10));
      return handle;
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }

  void _receive(dynamic message) {
    if (_closed) return;
    if (message is! Map) {
      _fault('Serial worker stopped');
      return;
    }
    switch (message['type']) {
      case 'ready':
        _commands = message['port'] as SendPort;
        if (!_ready.isCompleted) _ready.complete();
      case 'data':
        _input.add(message['bytes'] as Uint8List);
        _commands?.send({'op': 'ack'});
      case 'fault':
        _fault(message['error'] as String);
      case 'result':
        final pending = _pending.remove(message['id']);
        if (pending == null) return;
        if (message['error'] != null) {
          pending.completeError(
            SerialException('Serial driver error', message['error'] as String),
          );
        } else {
          pending.complete(message['value']);
        }
    }
  }

  void _fault(String detail) {
    final error = SerialException('Serial connection lost', detail);
    if (!_ready.isCompleted) {
      _ready.completeError(error);
    } else {
      _input.addError(error);
    }
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    unawaited(close());
  }

  Future<Object?> _request(String op, [Object? value]) async {
    if (_closed || _commands == null) {
      throw const SerialException('Serial port is not connected');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands!.send({'id': id, 'op': op, 'value': value});
    try {
      return await completer.future.timeout(const Duration(seconds: 2));
    } finally {
      _pending.remove(id);
    }
  }

  @override
  Stream<Uint8List> get input => _input.stream;
  @override
  Future<int> write(Uint8List bytes) async =>
      (await _request('write', bytes)) as int;
  @override
  Future<void> setSignal(SerialSignal signal, bool enabled) async {
    await _request('signal', {'signal': signal.name, 'enabled': enabled});
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    // The worker closes/disposes its handle before acknowledging. Kill is only
    // a fallback for a nonresponsive native driver.
    try {
      if (_commands != null) await _request('close');
    } catch (_) {
      /* stopped */
    }
    if (_closed) return;
    _closed = true;
    for (final pending in _pending.values) {
      pending.completeError(
        const SerialException('Serial port is not connected'),
      );
    }
    _pending.clear();
    _worker?.kill(priority: Isolate.immediate);
    await _subscription?.cancel();
    _messages.close();
    unawaited(_input.close());
  }
}

void _serialWorker(List<Object> args) {
  final events = args[0] as SendPort;
  final commands = ReceivePort();
  native.SerialPort? port;
  Timer? poll;
  var awaitingReadAck = false;
  void cleanup() {
    poll?.cancel();
    final owned = port;
    port = null;
    if (owned != null) {
      try {
        if (owned.isOpen) owned.close();
      } finally {
        owned.dispose();
      }
    }
    commands.close();
  }

  try {
    final config = SerialConfig.fromJson(
      Map<String, dynamic>.from(args[2] as Map),
    );
    final owned = native.SerialPort(args[1] as String);
    port = owned;
    if (!owned.openReadWrite()) {
      throw StateError(native.SerialPort.lastError.toString());
    }
    applySerialPortConfig(owned, (settings) {
      settings.baudRate = config.baudRate;
      settings.bits = config.dataBits;
      settings.parity = config.parity.index;
      settings.stopBits = config.stopBits;
      settings.setFlowControl(switch (config.flowControl) {
        SerialFlowControl.none => native.SerialPortFlowControl.none,
        SerialFlowControl.rtsCts => native.SerialPortFlowControl.rtsCts,
        SerialFlowControl.xonXoff => native.SerialPortFlowControl.xonXoff,
      });
      // Explicit idle levels: presets otherwise assert DTR/RTS automatically.
      settings.dtr = native.SerialPortDtr.off;
      if (config.flowControl != SerialFlowControl.rtsCts) {
        settings.rts = native.SerialPortRts.off;
      }
    });
    events.send({'type': 'ready', 'port': commands.sendPort});
    poll = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (port == null || awaitingReadAck) return;
      try {
        final count = owned.bytesAvailable;
        if (count > 0) {
          final data = owned.read(count.clamp(0, 16384));
          if (data.isNotEmpty) {
            awaitingReadAck = true;
            events.send({'type': 'data', 'bytes': data});
          }
        }
      } catch (error) {
        events.send({'type': 'fault', 'error': error.toString()});
        cleanup();
      }
    });
    commands.listen((dynamic command) {
      if (command['op'] == 'ack') {
        awaitingReadAck = false;
        return;
      }
      final id = command['id'];
      try {
        Object? value;
        switch (command['op']) {
          case 'write':
            value = owned.write(command['value'] as Uint8List);
          case 'signal':
            final signal = command['value'] as Map;
            final enabled = signal['enabled'] as bool;
            if (signal['signal'] == SerialSignal.breakSignal.name) {
              final ok = enabled ? owned.startBreak() : owned.endBreak();
              if (!ok) throw StateError(native.SerialPort.lastError.toString());
            } else {
              applySerialPortConfig(owned, (update) {
                if (signal['signal'] == SerialSignal.dtr.name) {
                  update.dtr = enabled ? 1 : 0;
                } else {
                  update.rts = enabled ? 1 : 0;
                }
              });
            }
          case 'close':
            cleanup();
        }
        events.send({'type': 'result', 'id': id, 'value': value});
      } catch (error) {
        events.send({'type': 'result', 'id': id, 'error': error.toString()});
      }
    });
  } catch (error) {
    events.send({'type': 'fault', 'error': error.toString()});
    cleanup();
  }
}

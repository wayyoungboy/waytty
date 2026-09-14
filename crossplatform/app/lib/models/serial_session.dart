import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/serial/serial_backend.dart';
import 'app_session.dart';
import 'serial_models.dart';

/// Owns the only reader and writer for this open serial session. A closed
/// session cannot be reopened: reconnect creates a fresh identity and queue.
class SerialSession extends ChangeNotifier implements AppSession {
  SerialSession({
    required this.device,
    required this.config,
    required this._backend,
    this.maxCaptureBytes = 512 * 1024,
  }) {
    if (maxCaptureBytes < 1) throw ArgumentError.value(maxCaptureBytes);
  }
  final SerialDeviceInfo device;
  final SerialConfig config;
  final SerialBackend _backend;
  final int maxCaptureBytes;
  @override
  final String id = const Uuid().v4();
  @override
  String? customLabel;
  @override
  String? colorTag;
  @override
  bool isPinned = false;
  @override
  String get tabLabel => customLabel ?? device.label;
  SerialStatus status = SerialStatus.idle;
  String? errorKey, errorDetail;
  int receivedBytes = 0, sentBytes = 0, discardedBytes = 0;
  int _captureBytes = 0;
  final _records = Queue<SerialRecord>();
  List<SerialRecord> get records => List.unmodifiable(_records);
  SerialHandle? _handle;
  StreamSubscription<Uint8List>? _subscription;
  bool _disposed = false, _sending = false;
  int _sendEpoch = 0;
  bool get sending => _sending;
  bool get connected => status == SerialStatus.connected;
  Timer? _notification;
  Future<void>? _releaseFuture;
  VoidCallback? onStateChanged;

  Uint8List get rawReceived => Uint8List.fromList([
    for (final r in _records)
      if (!r.transmitted) ...r.bytes,
  ]);
  // Decode the bounded continuous capture, so UTF-8 split across reads joins
  // correctly. Original bytes remain available even for malformed sequences.
  String get receivedText => utf8.decode(rawReceived, allowMalformed: true);

  void _notify({bool state = false}) {
    if (_disposed) return;
    if (state) onStateChanged?.call();
    _notification ??= Timer(const Duration(milliseconds: 40), () {
      _notification = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> connect() async {
    if (_disposed || status != SerialStatus.idle) return;
    status = SerialStatus.connecting;
    _notify(state: true);
    try {
      config.validate();
      final handle = await _backend.open(device, config);
      if (_disposed || status != SerialStatus.connecting) {
        await handle.close();
        return;
      }
      _handle = handle;
      status = SerialStatus.connected;
      _subscription = handle.input.listen(
        (bytes) {
          if (!connected || bytes.isEmpty) return;
          receivedBytes += bytes.length;
          _capture(bytes, false);
        },
        onError: (Object error) {
          _fail('Serial connection lost', error);
        },
        onDone: () {
          if (!connected) return;
          status = SerialStatus.disconnected;
          unawaited(_release());
          _notify(state: true);
        },
      );
      _notify(state: true);
    } catch (error) {
      if (status != SerialStatus.closed && !_disposed) {
        _fail(
          error is SerialException ? error.key : 'Cannot open serial port',
          error,
        );
      }
    }
  }

  void _capture(Uint8List bytes, bool tx) {
    _records.add(
      SerialRecord(time: DateTime.now(), transmitted: tx, bytes: bytes),
    );
    _captureBytes += bytes.length;
    while (_captureBytes > maxCaptureBytes || _records.length > 2048) {
      final oldest = _records.removeFirst();
      final excess = _captureBytes - maxCaptureBytes;
      final trim = _records.length >= 2048
          ? oldest.bytes.length
          : excess.clamp(1, oldest.bytes.length);
      _captureBytes -= trim;
      discardedBytes += trim;
      if (trim < oldest.bytes.length) {
        _records.addFirst(
          SerialRecord(
            time: oldest.time,
            transmitted: oldest.transmitted,
            bytes: Uint8List.sublistView(oldest.bytes, trim),
          ),
        );
      }
    }
    _notify();
  }

  void clearCapture() {
    _records.clear();
    _captureBytes = 0;
    discardedBytes = 0;
    _notify();
  }

  Future<void> send(Uint8List bytes) async {
    final handle = _handle;
    if (!connected || handle == null) {
      throw const SerialException('Serial port is not connected');
    }
    if (_sending) throw const SerialException('Serial send is busy');
    if (bytes.length > 65536) {
      throw const SerialException('Serial send exceeds 64 KiB');
    }
    final payload = Uint8List.fromList(bytes);
    final epoch = _sendEpoch;
    _sending = true;
    _notify();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var offset = 0;
    try {
      while (offset < payload.length) {
        if (epoch != _sendEpoch) {
          throw const SerialException(
            'Serial send stopped; submitted bytes cannot be recalled',
          );
        }
        if (!connected || !identical(handle, _handle)) {
          throw const SerialException('Serial write outcome is unknown');
        }
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Serial write timed out');
        }
        final chunk = Uint8List.sublistView(
          payload,
          offset,
          (offset + 4096).clamp(0, payload.length),
        );
        final count = await handle
            .write(chunk)
            .timeout(const Duration(seconds: 2));
        if (!connected || !identical(handle, _handle)) {
          throw const SerialException('Serial write outcome is unknown');
        }
        if (count < 0 || count > chunk.length) {
          throw StateError('Invalid driver write count');
        }
        if (count == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        sentBytes += count;
        _capture(Uint8List.sublistView(chunk, 0, count), true);
        offset += count;
        if (epoch != _sendEpoch) {
          throw const SerialException(
            'Serial send stopped; submitted bytes cannot be recalled',
          );
        }
      }
    } catch (error) {
      if (error is SerialException &&
          error.key ==
              'Serial send stopped; submitted bytes cannot be recalled') {
        rethrow;
      }
      if (connected) _fail('Serial write outcome is unknown', error);
      throw SerialException(
        'Serial write outcome is unknown',
        error.toString(),
      );
    } finally {
      _sending = false;
      _notify();
    }
  }

  void cancelSend() {
    _sendEpoch++;
  }

  Future<void> setSignal(SerialSignal signal, bool value) async {
    final handle = _handle;
    if (!connected || handle == null) {
      throw const SerialException('Serial port is not connected');
    }
    if (signal == SerialSignal.rts &&
        config.flowControl == SerialFlowControl.rtsCts) {
      throw const SerialException('RTS is managed by hardware flow control');
    }
    try {
      await handle.setSignal(signal, value).timeout(const Duration(seconds: 2));
    } catch (error) {
      throw SerialException('Serial signal control failed', error.toString());
    }
  }

  void _fail(String key, Object error) {
    if (_disposed || status == SerialStatus.closed) return;
    status = SerialStatus.error;
    errorKey = key;
    errorDetail = error is SerialException ? error.detail : error.toString();
    unawaited(_release());
    _notify(state: true);
  }

  Future<void> _release() => _releaseFuture ??= () async {
    final handle = _handle;
    _handle = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await handle?.close();
    } catch (error) {
      errorKey ??= 'Serial close failed';
      errorDetail ??= error.toString();
    }
  }();

  Future<void> close() async {
    final wasConnecting = status == SerialStatus.connecting;
    status = SerialStatus.closed;
    _notify(state: true);
    if (wasConnecting && _backend is CancellableSerialBackend) {
      try {
        await (_backend).cancelOpen(device);
      } catch (error) {
        errorDetail ??= error.toString();
      }
    }
    await _release();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _notification?.cancel();
    onStateChanged = null;
    unawaited(close());
    super.dispose();
  }
}

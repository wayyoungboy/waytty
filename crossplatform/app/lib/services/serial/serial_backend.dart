import 'dart:typed_data';
import '../../models/serial_models.dart';

abstract interface class SerialBackend {
  Future<List<SerialDeviceInfo>> listDevices();
  Future<SerialHandle> open(SerialDeviceInfo device, SerialConfig config);
}

abstract interface class SerialHandle {
  Stream<Uint8List> get input;

  /// Number accepted by the driver, not acknowledgement from the device.
  Future<int> write(Uint8List bytes);
  Future<void> setSignal(SerialSignal signal, bool enabled);
  Future<void> close();
}

abstract interface class CancellableSerialBackend implements SerialBackend {
  Future<void> cancelOpen(SerialDeviceInfo device);
}

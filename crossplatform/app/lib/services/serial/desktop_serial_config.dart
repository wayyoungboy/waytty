import 'package:flutter_libserialport/flutter_libserialport.dart' as native;

/// Configure locally, then transfer ownership to the port exactly once.
///
/// libserialport 0.3.0+1's config setter caches the object before the native
/// sp_set_config call. It owns the config even if that call throws, and frees
/// it on replacement or port.dispose(). Only failures before the setter leave
/// cleanup to us. Disposing an adopted config here causes a native double free.
void applySerialPortConfig(
  native.SerialPort port,
  void Function(native.SerialPortConfig) configure,
) {
  final settings = native.SerialPortConfig();
  var transferred = false;
  try {
    configure(settings);
    transferred = true;
    port.config = settings;
  } finally {
    if (!transferred) settings.dispose();
  }
}

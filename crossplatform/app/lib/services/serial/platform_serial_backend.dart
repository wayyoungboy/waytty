import 'dart:io';
import 'android_serial_backend.dart';
import 'desktop_serial_backend.dart';
import 'serial_backend.dart';

SerialBackend createSerialBackend() =>
    Platform.isAndroid ? AndroidSerialBackend() : DesktopSerialBackend();

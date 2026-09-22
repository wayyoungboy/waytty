// Runs in a separate Dart process: a regression must fail a test, not abort the
// Flutter test runner. Uses the real libserialport config allocator and Dart
// ownership rules, but a null port so no hardware is enumerated or opened.
import 'dart:io';
import 'package:flutter_libserialport/flutter_libserialport.dart' as native;
import 'package:yourssh/services/serial/desktop_serial_config.dart';

class _SetterFailure implements Exception {}

class _FailingPort implements native.SerialPort {
  final native.SerialPort owner;
  _FailingPort(this.owner);

  @override
  set config(native.SerialPortConfig config) {
    // The actual dependency adopts before attempting native configuration.
    try {
      owner.config = config;
    } on native.SerialPortError {
      // A null port deliberately cannot apply OS settings.
    }
    throw _SetterFailure();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void apply(
  native.SerialPort port,
  void Function(native.SerialPortConfig) edit,
) {
  try {
    applySerialPortConfig(port, edit);
  } on native.SerialPortError {
    // Invalid null port is expected; its adopted config must remain alive.
  }
}

void check(bool condition) {
  if (!condition) throw StateError('Native config lifetime check failed');
}

void main(List<String> args) {
  final port = native.SerialPort.fromAddress(0);
  try {
    switch (args.single) {
      case 'replace':
        for (var i = 0; i < 1000; i++) {
          apply(port, (settings) {
            settings.baudRate = 115200 + i;
            settings.bits = 8;
            settings.parity = native.SerialPortParity.none;
            settings.stopBits = 1;
            settings.setFlowControl(native.SerialPortFlowControl.none);
            settings.dtr = native.SerialPortDtr.off;
            settings.rts = native.SerialPortRts.off;
          });
          check(port.config.baudRate == 115200 + i);
          apply(port, (settings) => settings.dtr = native.SerialPortDtr.on);
          check(port.config.dtr == native.SerialPortDtr.on);
          apply(port, (settings) => settings.rts = native.SerialPortRts.off);
          check(port.config.rts == native.SerialPortRts.off);
        }
      case 'setter-error':
        for (var i = 0; i < 1000; i++) {
          try {
            applySerialPortConfig(
              _FailingPort(port),
              (settings) => settings.baudRate = 9600 + i,
            );
            throw StateError('Expected setter error');
          } on _SetterFailure {
            check(port.config.baudRate == 9600 + i);
          }
        }
      case 'prepare-error':
        apply(port, (settings) => settings.baudRate = 19200);
        final previous = port.config;
        for (var i = 0; i < 1000; i++) {
          try {
            applySerialPortConfig(port, (settings) {
              settings.baudRate = 9600;
              throw const FormatException('fixture setup failure');
            });
            throw StateError('Expected preparation error');
          } on FormatException {
            check(identical(previous, port.config));
            check(port.config.baudRate == 19200);
          }
        }
      default:
        throw ArgumentError('Unknown probe mode');
    }
  } finally {
    port.dispose();
  }
  stdout.writeln('PASS ${args.single}: 1000 iterations; owner disposed');
}

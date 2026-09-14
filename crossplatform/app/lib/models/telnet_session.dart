import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';
import '../services/telnet_codec.dart';
import 'host.dart';
import 'terminal_session.dart';

enum TelnetStatus { connecting, connected, closed, error }

class TelnetSession extends ChangeNotifier implements TerminalSession {
  TelnetSession(this.host);
  final Host host;
  @override
  final String id = const Uuid().v4();
  @override
  final Terminal terminal = Terminal(maxLines: 10000);
  @override
  String? customLabel;
  @override
  String? colorTag;
  @override
  bool isPinned = false;
  @override
  String get tabLabel => customLabel ?? host.label;
  @override
  bool get isLocal => false;
  @override
  String get recordingFolder => host.id;
  @override
  String get recordingTitle => '${host.label} · Telnet';

  TelnetStatus status = TelnetStatus.connecting;
  String? error;
  Socket? _socket;
  bool _closed = false;
  void Function(String sessionId, String text)? onOutput;
  void Function(String sessionId)? onClosed;

  Future<void> connect() async {
    try {
      final socket = await Socket.connect(
        host.host,
        host.port,
        timeout: const Duration(seconds: 15),
      );
      if (_closed) {
        socket.destroy();
        return;
      }
      _socket = socket;
      socket.setOption(SocketOption.tcpNoDelay, true);
      final codec = TelnetCodec(
        send: socket.add,
        terminalType: host.termType ?? 'xterm-256color',
      );
      terminal.onOutput = codec.write;
      terminal.onResize = (w, h, pw, ph) => codec.resize(w, h);
      codec.resize(terminal.viewWidth, terminal.viewHeight);
      final decoded = const Utf8Decoder(allowMalformed: true)
          .startChunkedConversion(
            StringConversionSink.fromStringSink(
              _TerminalSink((text) {
                terminal.write(text);
                onOutput?.call(id, text);
              }),
            ),
          );
      socket.listen(
        (data) => decoded.add(codec.receive(data)),
        onDone: () {
          decoded.close();
          if (_closed) return;
          status = TelnetStatus.closed;
          terminal.write('\r\n[连接已关闭]\r\n');
          onClosed?.call(id);
          notifyListeners();
        },
        onError: (Object e) {
          if (_closed) return;
          error = e.toString();
          status = TelnetStatus.error;
          terminal.write('\r\n[连接错误: $error]\r\n');
          socket.destroy();
          onClosed?.call(id);
          notifyListeners();
        },
      );
      status = TelnetStatus.connected;
      notifyListeners();
    } catch (e) {
      if (_closed) return;
      error = e.toString();
      status = TelnetStatus.error;
      notifyListeners();
    }
  }

  void close() {
    _closed = true;
    terminal.onOutput = null;
    terminal.onResize = null;
    _socket?.destroy();
    status = TelnetStatus.closed;
    onClosed?.call(id);
  }
}

class _TerminalSink implements StringSink {
  _TerminalSink(this.emit);
  final void Function(String) emit;
  @override
  void write(Object? object) => emit('$object');
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      emit(objects.join(separator));
  @override
  void writeCharCode(int charCode) => emit(String.fromCharCode(charCode));
  @override
  void writeln([Object? object = '']) => emit('$object\n');
}

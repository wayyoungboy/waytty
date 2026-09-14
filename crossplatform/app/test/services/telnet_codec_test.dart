import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/telnet_session.dart';
import 'package:yourssh/services/telnet_codec.dart';

void main() {
  test('negotiation and UTF-8 payload survive every possible packet split', () {
    final packet = [255, 251, 1, ...utf8.encode('中文'), 13, 0, 255, 255, 65];
    for (var split = 0; split <= packet.length; split++) {
      final sent = <int>[];
      final codec = TelnetCodec(send: sent.addAll);
      final payload = [...codec.receive(packet.sublist(0, split)), ...codec.receive(packet.sublist(split))];
      expect(payload, [...utf8.encode('中文'), 13, 255, 65], reason: 'split $split');
      expect(sent, [255, 253, 1]);
    }
  });
  test('duplicate acknowledgments do not loop and disabling options is honored', () {
    final sent = <int>[];
    final codec = TelnetCodec(send: sent.addAll);
    codec.receive([255, 251, 1, 255, 251, 1, 255, 252, 1, 255, 252, 1]);
    expect(sent, [255, 253, 1, 255, 254, 1]);
    expect(codec.remoteEcho, false);
    codec.receive([255, 253, 99, 255, 251, 99]);
    expect(sent.sublist(6), [255, 252, 99, 255, 254, 99]);
  });
  test('NAWS escapes IAC in 16-bit dimensions, TTYPE answers SEND only', () {
    final sent = <int>[];
    final codec = TelnetCodec(send: sent.addAll);
    codec.resize(255, 511);
    codec.receive([255, 253, 31]);
    expect(sent, [255, 251, 31, 255, 250, 31, 0, 255, 255, 1, 255, 255, 255, 240]);
    sent.clear();
    codec.receive([255, 253, 24, 255, 250, 24, 1, 255]);
    codec.receive([240]);
    expect(sent, [255, 251, 24, 255, 250, 24, 0, ...ascii.encode('xterm-256color'), 255, 240]);
  });
  test('NVT Return and LF normalize without doubling CRLF', () {
    final sent = <int>[];
    final codec = TelnetCodec(send: sent.addAll);
    codec.write('a\rb\nc\r\n');
    expect(sent, ascii.encode('a\r\nb\r\nc\r\n'));
  });
  test('real loopback session negotiates, receives Unicode and closes', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<List<int>>();
    Socket? peer;
    server.listen((socket) {
      peer = socket;
      socket.add([255, 251, 1, ...utf8.encode('你好\r\n')]);
      final input = <int>[];
      socket.listen((bytes) {
        input.addAll(bytes);
        if (input.contains(120) && !received.isCompleted) received.complete(input);
      });
    });
    final session = TelnetSession(Host(label: 'loopback', host: '127.0.0.1',
      username: '', port: server.port, protocol: HostProtocol.telnet));
    final output = Completer<void>();
    session.onOutput = (_, text) { if (text.contains('你好') && !output.isCompleted) output.complete(); };
    try {
      await session.connect();
      await output.future.timeout(const Duration(seconds: 5));
      session.terminal.onOutput!('x\r');
      expect(await received.future.timeout(const Duration(seconds: 5)), containsAllInOrder([255, 253, 1, 120, 13, 10]));
      expect(session.status, TelnetStatus.connected);
    } finally {
      session.close(); session.dispose(); peer?.destroy(); await server.close();
    }
  });
}

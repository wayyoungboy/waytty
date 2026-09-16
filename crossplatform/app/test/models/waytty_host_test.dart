import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/import_panel.dart';

void main() {
  test('Telnet with no login name survives restart and import/export', () {
    final host = Host(label: '交换机', host: '127.0.0.1', username: '',
      protocol: HostProtocol.telnet, port: 2323, group: '机房/网络',
      favorite: true, connectionCount: 4, note: '控制台');
    final copy = Host.fromJson(host.toJson());
    expect(copy.protocol, HostProtocol.telnet);
    expect(copy.favorite, true);
    expect(copy.note, '控制台');
    expect(copy.copyWith(label: '重命名').connectionCount, 4);
    final imported = parseJsonHosts('[{"host":"127.0.0.1","username":"","protocol":"telnet","port":2323,"favorite":true}]').single;
    expect(imported.protocol, HostProtocol.telnet);
    expect(imported.port, 2323);
    expect(imported.favorite, true);
  });
}

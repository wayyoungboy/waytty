import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/system_snapshot.dart';

void main() {
  test('CPU guest counters are not double-counted', () {
    final s = SystemSnapshot.fromShellOutput('''
__CPU1__
cpu 100 0 0 900 0 0 0 0 50 0
__CPU2__
cpu 150 0 0 950 0 0 0 0 100 0
''');
    expect(s.cpuPercent, 50);
  });
  test(
    'load, swap and per-interface counters parse without loopback double counting',
    () {
      final s = SystemSnapshot.fromShellOutput('''
__LOAD__
0.25 0.50 0.75 2/100 222
__MEM__
MemTotal: 1000 kB
MemAvailable: 400 kB
SwapTotal: 200 kB
SwapFree: 50 kB
__NET__
lo: 10 0 0 0 0 0 0 0 10 0 0 0 0 0 0 0
eth0: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0
docker0: 3000 0 0 0 0 0 0 0 4000 0 0 0 0 0 0 0
bad: invalid
''');
      expect(s.loadAverages, [0.25, 0.50, 0.75]);
      expect(s.totalSwapBytes, 200 * 1024);
      expect(s.usedSwapBytes, 150 * 1024);
      expect(s.network.map((n) => n.interface), ['eth0', 'docker0']);
      expect(s.network.first.rxBytes, 1000);
      expect(s.network.first.txBytes, 2000);
    },
  );
  test('TCP and UDP listening on the same port remain distinct', () {
    final s = SystemSnapshot.fromShellOutput('''
__PORTS__
tcp LISTEN 0 128 0.0.0.0:53 0.0.0.0:* users:(("dns",pid=1,fd=3))
udp UNCONN 0 0 0.0.0.0:53 0.0.0.0:* users:(("dns",pid=1,fd=4))
''');
    expect(s.ports.map((p) => p.protocol), ['tcp', 'udp']);
  });
}

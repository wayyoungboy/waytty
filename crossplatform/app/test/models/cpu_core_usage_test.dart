import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/system_snapshot.dart';

SystemSnapshot sample(String before, String after) =>
    SystemSnapshot.fromShellOutput('__CPU1__\n$before\n__CPU2__\n$after\n');

void main() {
  test(
    'aggregate and individual cores use matching IDs, not row positions',
    () {
      final s = sample(
        '''
cpu 100 0 0 900 0 0 0 0 0 0
cpu10 40 0 0 460 0 0 0 0 0 0
cpu2 60 0 0 440 0 0 0 0 0 0
''',
        '''
cpu 150 0 0 950 0 0 0 0 0 0
cpu2 100 0 0 450 0 0 0 0 0 0
cpu10 50 0 0 500 0 0 0 0 0 0
''',
      );
      expect(s.cpuAvailable, isTrue);
      expect(s.cpuPercent, closeTo(50, .001));
      expect(s.cpuCorePercent.keys, [2, 10]);
      expect(s.cpuCorePercent[2], closeTo(80, .001));
      expect(s.cpuCorePercent[10], closeTo(20, .001));
    },
  );

  test(
    'new, stalled or reset cores remain unavailable instead of showing zero',
    () {
      final s = sample(
        '''
cpu0 100 0 0 900 0
cpu1 100 0 0 900 0
cpu2 100 0 0 900 0
cpu3 100 0 0 900 0
''',
        '''
cpu0 100 0 0 950 0
cpu1 100 0 0 900 0
cpu2 1 0 0 9 0
cpu4 100 0 0 900 0
''',
      );
      expect(s.cpuCorePercent, {0: 0.0, 1: null, 2: null, 4: null});
    },
  );

  test('guest counters are excluded for individual cores too', () {
    final s = sample(
      'cpu0 100 0 0 900 0 0 0 0 50 0',
      'cpu0 150 0 0 950 0 0 0 0 100 0',
    );
    expect(s.cpuCorePercent[0], 50);
  });

  test('malformed rows do not contaminate healthy cores', () {
    final s = sample(
      'cpu0 bad 0 0 900 0\ncpu1 100 0 0 900 0',
      'cpu0 150 0 0 950 0\ncpu1 150 0 0 950 0\ncpu2 3 -4 0 8 0\ncpuX 10 0 0 10 0',
    );
    expect(s.cpuCorePercent, {0: null, 1: 50.0});
  });

  test('aggregate-only snapshots remain compatible', () {
    final s = sample('cpu 100 0 0 900 0', 'cpu 150 0 0 950 0');
    expect(s.cpuCorePercent, isEmpty);
    expect(s.cpuPercent, 50);
  });
}

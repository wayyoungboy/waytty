import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/network_stats_service.dart';
import 'package:yourssh/services/ssh_service.dart';

typedef _Result = ({String stdout, String stderr, int exitCode});

class _Ssh extends Fake implements SshService {
  final pending = <Completer<_Result>>[];
  int autoConnectCalls = 0;
  Future<_Result> _probe() {
    final next = Completer<_Result>();
    pending.add(next);
    return next.future;
  }

  @override
  Future<_Result> exec(
    Host host,
    String command, {
    String? auditSource = 'app',
  }) {
    autoConnectCalls++;
    return _probe();
  }

  @override
  Future<_Result> execForMonitoring(Host host, String command) => _probe();
}

void main() {
  final host = Host(
    label: 'fixture',
    host: 'offline.invalid',
    port: 22,
    username: 'fixture',
  );
  test('slow network polls do not overlap or auto-connect', () {
    fakeAsync((clock) {
      final ssh = _Ssh();
      final service = NetworkStatsService(
        host: host,
        sshService: ssh,
        onUpdate: (_) {},
      );
      service.start();
      clock.elapse(const Duration(seconds: 7));
      expect(ssh.pending.length, 1);
      expect(ssh.autoConnectCalls, 0);
      service.stop();
    });
  });
  test('late network delta is discarded after stop', () {
    fakeAsync((clock) {
      final ssh = _Ssh();
      var updates = 0;
      final service = NetworkStatsService(
        host: host,
        sshService: ssh,
        onUpdate: (_) => updates++,
      );
      service.start();
      clock.elapse(const Duration(seconds: 2));
      ssh.pending.first.complete((
        stdout: 'eth0: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0',
        stderr: '',
        exitCode: 0,
      ));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 2));
      service.stop();
      ssh.pending.last.complete((
        stdout: 'eth0: 200 0 0 0 0 0 0 0 400 0 0 0 0 0 0 0',
        stderr: '',
        exitCode: 0,
      ));
      clock.flushMicrotasks();
      expect(updates, 0);
    });
  });
}

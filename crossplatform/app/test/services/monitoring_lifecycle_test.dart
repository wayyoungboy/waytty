import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/system_stats_service.dart';

typedef _Result = ({String stdout, String stderr, int exitCode});

class _Ssh extends Fake implements SshService {
  final pending = Completer<_Result>();
  int calls = 0;
  @override
  Future<_Result> execForMonitoring(Host host, String command) {
    calls++;
    return pending.future;
  }
}

void main() {
  final host = Host(
    label: 'fixture',
    host: 'offline.invalid',
    port: 22,
    username: 'fixture',
  );
  test('monitor probes never reconnect an offline host', () async {
    var attempts = 0;
    final ssh = SshService(StorageService())
      ..defaultHostKeyVerifier = (_, port, type, fingerprint, {attempt}) async {
        attempts++;
        return true;
      };
    await expectLater(ssh.execForMonitoring(host, 'true'), throwsStateError);
    expect(attempts, 0);
  });
  test(
    'overlapping probes coalesce and stopped service drops late errors',
    () async {
      final ssh = _Ssh();
      final errors = <Object>[];
      final service = SystemStatsService(
        host: host,
        sshService: ssh,
        onUpdate: (_) => fail('late update'),
        onError: errors.add,
      );
      final poll = service.poll();
      await service.poll();
      expect(ssh.calls, 1);
      service.stop();
      ssh.pending.completeError(StateError('late'));
      await poll;
      expect(errors, isEmpty);
    },
  );
  for (final output in ['', '__CPU1__\n\n__MEM__\n__UPTIME__\n']) {
    test(
      'empty or unsupported output produces an error instead of zero usage: $output',
      () async {
        final ssh = _Ssh();
        final errors = <Object>[];
        final service = SystemStatsService(
          host: host,
          sshService: ssh,
          onUpdate: (_) => fail('invalid snapshot'),
          onError: errors.add,
        );
        final poll = service.poll();
        ssh.pending.complete((stdout: output, stderr: '', exitCode: 0));
        await poll;
        expect(errors, hasLength(1));
      },
    );
  }
}

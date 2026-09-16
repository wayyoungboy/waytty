import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/bounded_ssh_exec.dart';
import '../helpers/secure_store.dart';

void main() {
  final python = Platform.environment['WAYTTY_SSH_FIXTURE_PYTHON'];
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real SSH authentication, UTF-8 exec, SFTP Unicode names and binary resume',
    () async {
      installSecureStoreMock();
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('waytty-sftp-fixture-');
      final server = await Process.start(python!, [
        'test/fixtures/ssh_server.py',
        root.path,
      ]);
      final errors = StringBuffer();
      server.stderr.transform(utf8.decoder).listen(errors.write);
      SshService? ssh;
      Host? host;
      try {
        final line = await server.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw StateError('$errors'),
            );
        final port = jsonDecode(line)['port'] as int;
        host = Host(
          label: 'fixture',
          host: '127.0.0.1',
          port: port,
          username: 'fixture',
        );
        final storage = StorageService();
        await storage.savePassword(host.id, 'fixture-only-password');
        ssh = SshService(storage)
          ..defaultHostKeyVerifier = (_, p, type, fp) async =>
              p == port && type == 'ssh-ed25519' && fp.isNotEmpty;
        final result = await ssh.exec(host, 'waytty-utf8-check');
        expect(result.stdout, '中文 SSH ✓\n');
        expect(result.stderr, '诊断信息\n');
        expect(result.exitCode, 7);
        final mcpResult = await ssh.execForMcp(host, 'waytty-utf8-check');
        expect(mcpResult.stdout, result.stdout);
        expect(mcpResult.stderr, result.stderr);
        expect(mcpResult.exitCode, 7);
        final monitorResult = await ssh.execForMonitoring(host, 'waytty-utf8-check');
        expect(monitorResult, result);
        await expectLater(
          ssh.execForMonitoring(host, 'waytty-large-output'),
          throwsStateError,
        );
        expect((await ssh.execForMonitoring(host, 'waytty-utf8-check')).exitCode, 7);
        await expectLater(
          ssh.execForMcp(host, 'waytty-large-output'),
          throwsStateError,
        );
        expect((await ssh.execForMcp(host, 'waytty-utf8-check')).exitCode, 7);
        final timeoutClient = SSHClient(
          await SSHSocket.connect(host.host, port),
          username: 'fixture',
          onPasswordRequest: () => 'fixture-only-password',
          onVerifyHostKey: (type, fp) => type == 'ssh-ed25519' && fp.isNotEmpty,
        );
        try {
          await timeoutClient.authenticated;
          await expectLater(
            boundedSshExec(
              timeoutClient,
              'waytty-wait',
              timeout: const Duration(milliseconds: 100),
            ),
            throwsA(isA<TimeoutException>()),
          );
          expect(
            (await boundedSshExec(timeoutClient, 'waytty-utf8-check')).exitCode,
            7,
          );
          // Exercise fast exits repeatedly: status packets can arrive with the
          // exec acknowledgement, before execute() returns to its caller.
          for (var i = 0; i < 20; i++) {
            final fast = await boundedSshExec(timeoutClient, 'waytty-utf8-check');
            expect(fast.exitCode, 7, reason: 'fast exec $i');
            expect(utf8.decode(fast.stdout), '中文 SSH ✓\n');
            expect(utf8.decode(fast.stderr), '诊断信息\n');
          }
        } finally {
          timeoutClient.close();
        }
        final shellClient = SSHClient(
          await SSHSocket.connect(host.host, port),
          username: 'fixture-fast-shell',
          onPasswordRequest: () => 'fixture-only-password',
          onVerifyHostKey: (type, fp) => type == 'ssh-ed25519' && fp.isNotEmpty,
        );
        try {
          await shellClient.authenticated;
          for (var i = 0; i < 10; i++) {
            final session = await shellClient.shell(pty: null);
            final output = <int>[];
            await Future.wait([
              session.stdout.forEach(output.addAll),
              session.stderr.drain<void>(),
              session.done,
            ]);
            expect(session.exitCode, 13, reason: 'fast shell $i');
            expect(utf8.decode(output), 'short shell\n');
          }
        } finally {
          shellClient.close();
        }
        final sftp = await ssh.openSftp(host);
        try {
          await sftp.mkdir('/测试目录');
          const path = '/测试目录/空 格 "引号".bin';
          final bytes = Uint8List.fromList(
            List.generate(262144, (i) => i % 251),
          );
          final remote = await sftp.open(
            path,
            mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
          );
          try {
            await remote.writeBytes(Uint8List.sublistView(bytes, 0, 100003));
            await remote.writeBytes(
              Uint8List.sublistView(bytes, 100003),
              offset: 100003,
            );
          } finally {
            await remote.close();
          }
          await sftp.rename(path, '/测试目录/已重命名.bin');
          await sftp.setStat(
            '/测试目录/已重命名.bin',
            SftpFileAttrs(mode: SftpFileMode.value(0x180)),
          );
          final read = await sftp.open('/测试目录/已重命名.bin');
          try {
            expect(await read.readBytes(), bytes);
          } finally {
            await read.close();
          }
          expect(
            (await sftp.listdir('/测试目录')).map((e) => e.filename),
            contains('已重命名.bin'),
          );
          await sftp.remove('/测试目录/已重命名.bin');
          await sftp.rmdir('/测试目录');
        } finally {
          sftp.close();
        }
      } finally {
        if (host != null) ssh?.disconnect(host.id);
        server.stdin.writeln('stop');
        await server.stdin.flush();
        await server.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            server.kill();
            return -1;
          },
        );
        await root.delete(recursive: true);
      }
    },
    skip: python == null
        ? 'Set WAYTTY_SSH_FIXTURE_PYTHON to a Python with asyncssh installed'
        : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}

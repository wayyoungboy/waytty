import 'dart:async';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

/// Bounds both SSH channel creation and output collection; only this channel
/// is closed on failure, so the interactive terminal stays connected.
Future<SSHRunResult> boundedSshExec(
  SSHClient client,
  String command, {
  Duration timeout = const Duration(seconds: 30),
  int maxBytes = 1024 * 1024,
}) async {
  final clock = Stopwatch()..start();
  final opening = client.execute(command);
  final session = await opening.timeout(
    timeout,
    onTimeout: () {
      unawaited(
        opening.then(
          (lateSession) => lateSession.close(),
          onError: (Object _) {},
        ),
      );
      throw TimeoutException('SSH channel open timed out', timeout);
    },
  );
  final stdout = BytesBuilder(copy: false), stderr = BytesBuilder(copy: false);
  var total = 0;
  Future<void> collect(Stream<Uint8List> stream, BytesBuilder target) async {
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > maxBytes) {
        throw StateError('Command output exceeds $maxBytes bytes');
      }
      target.add(chunk);
    }
  }

  try {
    await Future.wait([
      collect(session.stdout, stdout),
      collect(session.stderr, stderr),
      session.done,
    ], eagerError: true).timeout(timeout - clock.elapsed);
    return SSHRunResult(
      output: Uint8List(0),
      stdout: stdout.takeBytes(),
      stderr: stderr.takeBytes(),
      exitCode: session.exitCode,
      exitSignal: session.exitSignal,
    );
  } finally {
    session.close();
  }
}

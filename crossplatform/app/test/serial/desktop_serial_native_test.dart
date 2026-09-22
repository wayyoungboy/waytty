import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final library = Platform.environment['LIBSERIALPORT_PATH'];
  final dart = Platform.environment['WAYTTY_TEST_DART'];
  final enabled = library != null && dart != null;
  for (final mode in ['replace', 'setter-error', 'prepare-error']) {
    test(
      'native config ownership: $mode and port disposal',
      () async {
        final process = await Process.start(dart!, [
          '--packages=${Directory.current.path}/.dart_tool/package_config.json',
          'test/fixtures/serial_config_probe.dart',
          mode,
        ]);
        final stdoutText = process.stdout
            .transform(const SystemEncoding().decoder)
            .join();
        final stderrText = process.stderr
            .transform(const SystemEncoding().decoder)
            .join();
        int exitCode;
        try {
          exitCode = await process.exitCode.timeout(
            const Duration(seconds: 20),
          );
        } finally {
          process.kill();
        }
        final output = await stdoutText;
        final errors = await stderrText;
        expect(exitCode, 0, reason: '$output\n$errors');
        expect(output, contains('PASS $mode: 1000 iterations; owner disposed'));
      },
      skip: enabled
          ? false
          : 'Set LIBSERIALPORT_PATH and WAYTTY_TEST_DART for native fixture (no hardware).',
    );
  }
}

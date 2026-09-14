import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/serial_models.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'serial_session_test.dart' show FakeSerialBackend, device;

void main() {
  test(
    'serial tabs share the workspace without becoming SSH targets',
    () async {
      final provider = SessionProvider(
        SshService(StorageService()),
        TabMetadataService(),
      );
      final backend = FakeSerialBackend();
      final session = await provider.connectSerial(
        device,
        const SerialConfig(),
        backend,
      );
      expect(provider.activeSession, session);
      expect(provider.sshSessions, isEmpty);
      expect(provider.hostForSession(session.id), isNull);
      await expectLater(
        provider.connectSerial(device, const SerialConfig(), backend),
        throwsA(isA<SerialException>()),
      );
      provider.closeSession(session.id);
      await Future<void>.delayed(Duration.zero);
      expect(provider.sessions, isEmpty);
      expect(backend.handle.closes, 1);
      provider.dispose();
      await backend.handle.controller.close();
    },
  );
}

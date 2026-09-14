import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/models/serial_models.dart';
import 'package:yourssh/models/serial_session.dart';
import 'package:yourssh/services/serial/serial_profile_store.dart';
import 'package:yourssh/widgets/serial/serial_connection_panel.dart';
import 'package:yourssh/widgets/serial/serial_session_pane.dart';
import 'serial_session_test.dart' show FakeSerialBackend, device;

Widget app(Widget child, {Locale locale = const Locale('zh', 'CN')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: WayttyStrings.delegates,
      supportedLocales: WayttyStrings.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved profiles retain configuration and can be deleted', () async {
    final store = SerialProfileStore();
    final profile = SerialProfile(
      name: '开发板',
      config: const SerialConfig(baudRate: 9600),
    );
    await store.save(profile);
    final restored = (await SerialProfileStore().load()).single;
    expect(restored.name, '开发板');
    expect(restored.config.baudRate, 9600);
    await store.delete(profile.id);
    expect(await store.load(), isEmpty);
  });

  test(
    'corrupt profiles are retained instead of overwritten on save',
    () async {
      SharedPreferences.setMockInitialValues({
        'waytty.serial.profiles.v1': 'broken',
      });
      final store = SerialProfileStore();
      await expectLater(
        store.save(SerialProfile(name: 'board', config: const SerialConfig())),
        throwsFormatException,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'waytty.serial.profiles.v1',
        ),
        'broken',
      );
    },
  );

  testWidgets(
    'serial entry lists devices without opening and connects on demand',
    (tester) async {
      final backend = FakeSerialBackend();
      var connects = 0;
      await tester.pumpWidget(
        app(
          SerialConnectionPanel(
            backend: backend,
            onConnect: (selected, config, _) async {
              expect(selected.id, device.id);
              expect(config.baudRate, 115200);
              connects++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('串口调试'), findsOneWidget);
      expect(connects, 0);
      await tester.tap(find.byKey(const ValueKey('serial-connect')));
      await tester.pumpAndSettle();
      expect(connects, 1);
      expect(tester.takeException(), isNull);
      await backend.handle.controller.close();
    },
  );

  testWidgets('narrow English panel has no overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = FakeSerialBackend();
    await tester.pumpWidget(
      app(
        SerialConnectionPanel(backend: backend, onConnect: (_, _, _) async {}),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Serial debugger'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await backend.handle.controller.close();
  });

  testWidgets('session sends exact HEX and paused display still receives', (
    tester,
  ) async {
    final backend = FakeSerialBackend();
    final session = SerialSession(
      device: device,
      config: const SerialConfig(),
      backend: backend,
    );
    await session.connect();
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(SerialSessionPane(session: session)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('serial-send-hex')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('serial-send-input')),
      '00 FF 41',
    );
    await tester.tap(find.byKey(const ValueKey('serial-send')));
    await tester.pumpAndSettle();
    expect(backend.handle.writes.expand((b) => b), [0, 255, 65]);
    await tester.tap(find.byKey(const ValueKey('serial-pause')));
    backend.handle.controller.add(Uint8List.fromList([65, 66]));
    await tester.pumpAndSettle();
    expect(session.receivedBytes, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    await tester.pump();
    backend.handle.controller.close();
  });
}

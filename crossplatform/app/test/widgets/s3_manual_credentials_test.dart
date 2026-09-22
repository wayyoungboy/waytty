import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_devops/src/screens/s3_browser_screen.dart';

void main() {
  testWidgets(
    'S3 opens with empty manual inputs and never accesses the keychain',
    (tester) async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            throw PlatformException(code: 'forbidden-keychain-access');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: S3BrowserScreen())),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Add Bucket'));
      await tester.pumpAndSettle();
      expect(find.text('Memory only'), findsOneWidget);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.length, 6);
      expect(fields[4].controller!.text, isEmpty);
      expect(fields[5].controller!.text, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

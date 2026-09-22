import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_credentials.dart';
import 'package:yourssh/models/ssh_connection_attempt.dart';
import 'package:yourssh/widgets/ssh_credentials_dialog.dart';

void main() {
  testWidgets('disconnect dismisses its prompt and cancelled queued prompts never open', (tester) async {
    late ManualCredentialPrompts prompts;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: WayttyStrings.supportedLocales,
      localizationsDelegates: WayttyStrings.delegates,
      home: Builder(builder: (context) {
        prompts = ManualCredentialPrompts(() => context);
        return const Scaffold(body: Text('home'));
      }),
    ));
    Host host(String id) => Host(label: id, host: 'fixture.invalid', username: 'fixture');
    final first = SshConnectionAttempt();
    final queued = SshConnectionAttempt();
    final a = prompts.request(host('first'), first);
    final b = prompts.request(host('queued'), queued);
    await tester.pumpAndSettle();
    expect(find.byType(SshCredentialsDialog), findsOneWidget);
    queued.cancel();
    first.cancel();
    await tester.pumpAndSettle();
    expect(await a, isNull);
    expect(await b, isNull);
    expect(find.byType(SshCredentialsDialog), findsNothing);
    // A fresh attempt still works after the cancelled queue drains.
    final fresh = prompts.request(host('fresh'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(await fresh, isNull);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets(
    'private key must be pasted manually and multiline input is preserved',
    (tester) async {
      SshCredentials? result;
      final host = Host(
        label: 'fixture',
        host: 'fixture.invalid',
        username: 'fixture',
        authType: AuthType.privateKey,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: WayttyStrings.supportedLocales,
          localizationsDelegates: WayttyStrings.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await ManualCredentialPrompts(
                    () => context,
                  ).request(host);
                },
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      expect(find.text('手动 SSH 认证'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      expect(tester.widget<TextField>(fields.first).controller!.text, isEmpty);
      const pem =
          '-----BEGIN OPENSSH PRIVATE KEY-----\nfixture\n-----END OPENSSH PRIVATE KEY-----';
      await tester.enterText(fields.first, pem);
      await tester.enterText(fields.last, 'fixture-passphrase');
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      expect(result!.privateKey, pem);
      expect(result!.passphrase, 'fixture-passphrase');
      expect(result!.toString(), isNot(contains('fixture')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling does not return entered credentials', (tester) async {
    SshCredentials? result;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: WayttyStrings.supportedLocales,
        localizationsDelegates: WayttyStrings.delegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await ManualCredentialPrompts(() => context).request(
                  Host(
                    label: 'fixture',
                    host: 'fixture.invalid',
                    username: 'fixture',
                  ),
                );
                completed = true;
              },
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fixture-password');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
  });
}

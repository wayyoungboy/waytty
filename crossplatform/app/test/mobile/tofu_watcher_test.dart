import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/mobile/security/tofu_watcher.dart';
import 'package:yourssh/models/ssh_connection_attempt.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';
import 'package:yourssh/widgets/ssh_host_key_dialog.dart';

void main() {
  for (final locale in ['en', 'zh']) {
    testWidgets(
      'first trust and changed key require fingerprint review ($locale)',
      (tester) async {
        tester.view.physicalSize = const Size(420, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final kh = KnownHostsProvider.forTest([]);
        addTearDown(kh.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            supportedLocales: WayttyStrings.supportedLocales,
            localizationsDelegates: WayttyStrings.delegates,
            home: ChangeNotifierProvider.value(
              value: kh,
              child: const TofuWatcher(child: Scaffold(body: Text('home'))),
            ),
          ),
        );
        final fp1 = Uint8List.fromList(List.filled(16, 1));
        final fp2 = Uint8List.fromList(List.filled(16, 2));
        final first = kh.verifyHostKey(
          'fixture.invalid',
          2222,
          'ssh-ed25519',
          fp1,
        );
        await tester.pumpAndSettle();
        expect(find.byType(SshHostKeyDialog), findsOneWidget);
        expect(
          find.text(locale == 'zh' ? '信任此 SSH 服务器？' : 'Trust this SSH server?'),
          findsOneWidget,
        );
        expect(find.text('fixture.invalid:2222'), findsOneWidget);
        expect(find.text('ssh-ed25519'), findsOneWidget);
        expect(kh.hosts, isEmpty);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(await first, true);
        expect(kh.hosts.length, 1);
        expect(
          await kh.verifyHostKey('fixture.invalid', 2222, 'ssh-ed25519', fp1),
          true,
        );
        await tester.pumpAndSettle();
        expect(find.byType(SshHostKeyDialog), findsNothing);

        final mismatch = kh.verifyHostKey(
          'fixture.invalid',
          2222,
          'ssh-ed25519',
          fp2,
        );
        await tester.pumpAndSettle();
        expect(
          find.text(locale == 'zh' ? '主机密钥已更改' : 'Host key changed'),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();
        expect(await mismatch, false);
        expect(kh.hosts.single.fingerprint, List.filled(16, '01').join(':'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancellation closes only its trust dialog and advances queued requests',
    (tester) async {
      final kh = KnownHostsProvider.forTest([]);
      addTearDown(kh.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: kh,
            child: const TofuWatcher(child: Scaffold(body: Text('home'))),
          ),
        ),
      );
      final attempt = SshConnectionAttempt();
      final a = kh.verifyHostKey(
        'a',
        22,
        'ssh-ed25519',
        Uint8List(16),
        attempt: attempt,
      );
      final b = kh.verifyHostKey('b', 22, 'ssh-ed25519', Uint8List(16));
      await tester.pumpAndSettle();
      expect(find.text('a:22'), findsOneWidget);
      attempt.cancel();
      await tester.pumpAndSettle();
      expect(await a, false);
      expect(find.text('a:22'), findsNothing);
      expect(find.text('b:22'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(await b, false);
      expect(kh.hosts, isEmpty);
      expect(find.text('home'), findsOneWidget);
    },
  );
}

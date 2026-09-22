import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/providers/account_vault_provider.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/account_vault_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/account_vault_section.dart';
import 'package:yourssh/theme/app_theme.dart';

import '../providers/account_vault_provider_test.dart' show FakeAccountBackend;

void main() {
  testWidgets(
    'email registration validates password boundaries and waits for OTP',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final backend = FakeAccountBackend()..confirmationRequired = true;
      final account = AccountVaultProvider(
        config: const AccountCloudConfig(
          url: 'https://fixture.invalid',
        ),
        createBackend: () => backend,
      );
      final sync = SyncProvider(account: account);
      await sync.ready;
      final hosts = HostProvider(StorageService());
      await hosts.ready;
      addTearDown(sync.dispose);
      addTearDown(hosts.dispose);
      await tester.binding.setSurfaceSize(const Size(440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundaryKey = GlobalKey();
      if (const bool.fromEnvironment('WAYTTY_CAPTURE_TEST_IMAGES')) {
        await tester.runAsync(() async {
          for (final font in {
            'SF Pro Display': '/System/Library/Fonts/STHeiti Light.ttc',
            'MaterialIcons':
                'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          }.entries) {
            final loader = FontLoader(font.key)
              ..addFont(
                File(font.value).readAsBytes().then(ByteData.sublistView),
              );
            await loader.load();
          }
        });
      }
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: sync),
            ChangeNotifierProvider.value(value: hosts),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: WayttyStrings.delegates,
            supportedLocales: WayttyStrings.supportedLocales,
            home: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                body: ListView(children: const [AccountVaultSection()]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本地离线'), findsOneWidget);
      expect(find.text('账号邮箱'), findsNothing);
      await tester.tap(find.text('云端账号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('注册邮箱账号'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'fixture@example.com');
      await tester.enterText(fields.at(1), '12345678');
      await tester.enterText(fields.at(2), '12345678');
      await tester.tap(find.text('注册账号'));
      await tester.pumpAndSettle();
      expect(find.text('密码长度必须为 9–16 位。'), findsOneWidget);
      expect(backend.signIns, 0);
      await tester.enterText(fields.at(1), '123456789');
      await tester.enterText(fields.at(2), '123456789');
      await tester.tap(find.text('注册账号'));
      await tester.pumpAndSettle();
      expect(find.text('邮件验证码'), findsOneWidget);
      expect(find.text('60 秒后重新发送'), findsOneWidget);
      expect(find.text('保存到云端'), findsNothing);
      expect(account.signedIn, false);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('WAYTTY_CAPTURE_TEST_IMAGES')) {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/waytty-email-verification.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('验证邮箱'));
      await tester.pumpAndSettle();
      expect(account.signedIn, true);
      expect(find.text('保险库密码（9–16 位）'), findsOneWidget);
      expect(find.text('再次输入保险库密码'), findsOneWidget);
      await tester.tap(find.text('退出登录，使用本地模式'));
      await tester.pumpAndSettle();
      expect(sync.mode, DataMode.local);
      expect(account.signedIn, false);
      expect(backend.record, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

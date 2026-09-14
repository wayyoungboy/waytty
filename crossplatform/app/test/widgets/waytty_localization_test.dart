import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waytty_l10n/waytty_l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WayttyLanguage.instance.restore();
  });

  Widget app(Widget child) => ValueListenableBuilder<Locale>(
    valueListenable: WayttyLanguage.instance,
    builder: (_, locale, _) => MaterialApp(
      locale: locale,
      supportedLocales: WayttyStrings.supportedLocales,
      localizationsDelegates: WayttyStrings.delegates,
      home: Scaffold(body: child),
    ),
  );

  testWidgets('first launch is Chinese even on an English system', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(app(const LText('Settings')));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    final context = tester.element(find.byType(LText));
    expect(MaterialLocalizations.of(context).cancelButtonLabel, '取消');
  });

  testWidgets(
    'picker changes const subtrees and remembers choice after restart',
    (tester) async {
      await tester.pumpWidget(
        app(
          const Column(
            children: [LanguagePicker(), LText('Settings'), LText('新建连接')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('New connection'), findsOneWidget);
      expect(find.text('Interface language'), findsOneWidget);
      final restarted = WayttyLanguage();
      await restarted.restore();
      expect(restarted.value, const Locale('en'));
      restarted.dispose();
    },
  );

  test(
    'arguments and explicitly raw labels are never translated or re-expanded',
    () {
      const zh = WayttyStrings(Locale('zh', 'CN'));
      const userText = 'Settings {0}\n中文 🖥';
      expect(zh.resolve(const LRaw('Settings')), 'Settings');
      expect(zh.resolve(const LMessage('{0} days', [userText])), '$userText 天');
      expect(
        zh.resolve(const LMessage('{0} days', [LRaw('Settings')])),
        'Settings 天',
      );
      expect(zh.resolve('Settings'), '设置');
      expect(const WayttyStrings(Locale('en')).resolve('设置'), 'Settings');
    },
  );

  test(
    'unsupported saved locale falls back to Chinese; rapid choices keep last value',
    () async {
      SharedPreferences.setMockInitialValues({
        WayttyLanguage.preferenceKey: 'xx',
      });
      final language = WayttyLanguage();
      await language.restore();
      expect(language.value, const Locale('zh', 'CN'));
      await Future.wait([
        language.select('en'),
        language.select('zh'),
        language.select('en'),
      ]);
      expect(language.value, const Locale('en'));
      final restarted = WayttyLanguage();
      await restarted.restore();
      expect(restarted.value, language.value);
      await expectLater(language.select('xx'), throwsArgumentError);
      restarted.dispose();
      language.dispose();
    },
  );

  test(
    'macOS menu bridge follows the same saved locale and translation catalog',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      const channel = MethodChannel('waytty/localization');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
          });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final language = WayttyLanguage();
      await language.restore();
      expect(calls.last.method, 'setLanguage');
      expect(calls.last.arguments['titles']['Edit'], '编辑');
      await language.select('en');
      expect(calls.last.arguments['titles']['Edit'], 'Edit');
      language.dispose();
    },
  );

  for (final width in [360.0, 900.0, 1280.0]) {
    testWidgets('language selector fits $width px in both languages', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(
          const Padding(padding: EdgeInsets.all(16), child: LanguagePicker()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await WayttyLanguage.instance.select('en');
      await tester.pumpAndSettle();
      expect(find.text('Interface language'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

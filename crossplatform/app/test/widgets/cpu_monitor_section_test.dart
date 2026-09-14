import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/models/system_snapshot.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/widgets/cpu_monitor_section.dart';

SystemSnapshot snapshot(Map<int, double?> cores) => SystemSnapshot(
  cpuPercent: 48.0,
  cpuCorePercent: cores,
  totalMemBytes: 1000,
  usedMemBytes: 500,
  disks: const [],
  uptime: const Duration(hours: 1),
  ports: const [],
  timestamp: DateTime(2026),
);

void main() {
  Widget app(SystemSnapshot value, {Locale locale = const Locale('zh')}) =>
      MaterialApp(
        theme: buildAppTheme(),
        locale: locale,
        supportedLocales: WayttyStrings.supportedLocales,
        localizationsDelegates: WayttyStrings.delegates,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 308,
              child: SingleChildScrollView(
                child: CpuMonitorSection(
                  snapshot: value,
                  history: [value, value],
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> choose(WidgetTester t, String label) async {
    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  testWidgets(
    'overall, all cores and one core are selectable at sidebar width',
    (t) async {
      await t.pumpWidget(app(snapshot({0: 23.0, 1: 81.0})));
      expect(find.text('48.0%'), findsOneWidget);
      expect(find.text('23.0%'), findsNothing);
      await choose(t, '全部核心');
      expect(find.text('23.0%'), findsOneWidget);
      expect(find.text('81.0%'), findsOneWidget);
      await choose(t, '核心 1');
      expect(find.text('81.0%'), findsOneWidget);
      expect(find.text('23.0%'), findsNothing);
      expect(find.text('48.0%'), findsNothing);
      await t.pumpWidget(app(snapshot({0: 24.0, 1: 92.0})));
      expect(find.text('92.0%'), findsOneWidget);
      await choose(t, '总体');
      expect(find.text('48.0%'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'offline selection falls back to overall; warming core is not zero',
    (t) async {
      await t.pumpWidget(app(snapshot({0: 10.0, 7: null})));
      await choose(t, '核心 7');
      expect(find.text('等待有效采样'), findsOneWidget);
      expect(find.text('0.0%'), findsNothing);
      await t.pumpWidget(app(snapshot({0: 25.0})));
      expect(find.text('48.0%'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('all cores remain scrollable on a 128-core host', (t) async {
    await t.pumpWidget(
      app(snapshot({for (var i = 0; i < 128; i++) i: i % 100 + .1})),
    );
    await choose(t, '全部核心');
    await t.scrollUntilVisible(
      find.text('核心 127'),
      240,
      scrollable: find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('核心 127'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'selection survives language switching and absent per-core data is explicit',
    (t) async {
      final value = snapshot({0: 10.0, 1: 20.0});
      await t.pumpWidget(app(value));
      await choose(t, '核心 1');
      await t.pumpWidget(app(value, locale: const Locale('en')));
      expect(find.text('20.0%'), findsOneWidget);
      expect(find.text('Core 1'), findsWidgets);
      await choose(t, 'All cores');
      expect(t.takeException(), isNull);
      await t.pumpWidget(app(snapshot({})));
      expect(find.text('48.0%'), findsOneWidget);
      expect(find.text('暂无各核心数据'), findsOneWidget);
    },
  );
}

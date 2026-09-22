import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/widgets/connection_center.dart';

void main() {
  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['WAYTTY_UX_PREVIEW'];
    if (directory == null) return;
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('connection-preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    List<Host> data = const [],
    VoidCallback? onImport,
    ValueChanged<Host>? onConnect,
    Locale locale = const Locale('en'),
    double width = 1280,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final hosts = HostProvider(StorageService());
    await hosts.ready;
    for (final host in data) {
      await hosts.addHost(host);
    }
    addTearDown(hosts.dispose);
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (Platform.environment.containsKey('WAYTTY_UX_PREVIEW')) {
      await tester.runAsync(() async {
        for (final entry in {
          'SF Pro Display': '/System/Library/Fonts/STHeiti Light.ttc',
          'MaterialIcons':
              'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(
              File(entry.value).readAsBytes().then(ByteData.sublistView),
            );
          await loader.load();
        }
      });
    }
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: hosts,
        child: MaterialApp(
          theme: buildAppTheme(),
          locale: locale,
          localizationsDelegates: WayttyStrings.delegates,
          supportedLocales: WayttyStrings.supportedLocales,
          home: RepaintBoundary(
            key: const ValueKey('connection-preview'),
            child: Scaffold(
              body: ConnectionCenter(
                onAdd: (_, _) {},
                onEdit: (_) {},
                onConnect: (host) async => onConnect?.call(host),
                onImport: onImport ?? () {},
                onNewGroup: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final web = Host(
    label: 'Web North',
    host: '2001:db8::1',
    username: 'deploy',
    group: 'Production',
    note: 'customer portal',
    tags: ['env:prod'],
  );
  final db = Host(
    label: 'Database South',
    host: 'db.example',
    username: 'reader',
  );

  testWidgets('search combines fields and ignores case and whitespace', (
    tester,
  ) async {
    await pump(tester, data: [web, db]);
    for (final query in [
      '  WEB   deploy  ',
      'production portal',
      '2001:db8::1',
      'env:prod north',
    ]) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(find.text('Web North'), findsOneWidget);
      expect(find.text('Database South'), findsNothing);
    }
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pumpAndSettle();
    expect(find.text('Database South'), findsOneWidget);
  });

  testWidgets('no results can clear search and reset an empty filter', (
    tester,
  ) async {
    await pump(tester, data: [web]);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching connections'), findsOneWidget);
    await capture(tester, 'connections-no-results-en');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Web North'), findsOneWidget);
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    expect(find.text('Web North'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bulk action counts and connects only visible selected hosts', (
    tester,
  ) async {
    final connected = <String>[];
    await pump(
      tester,
      data: [web, db],
      onConnect: (host) => connected.add(host.id),
    );
    await tester.tap(find.text('Web North'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Database South'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'north');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect selected (1)'));
    await tester.pumpAndSettle();
    expect(connected, [web.id]);
    await capture(tester, 'connections-search-en');
  });

  testWidgets('new workspace offers import in Chinese', (tester) async {
    var imported = false;
    await pump(
      tester,
      locale: const Locale('zh', 'CN'),
      onImport: () => imported = true,
    );
    await tester.tap(find.text('导入连接'));
    expect(imported, isTrue);
    expect(find.text('添加连接'), findsOneWidget);
    await capture(tester, 'connections-first-use-zh');
    expect(tester.takeException(), isNull);
  });

  testWidgets('English actions fit a compact connection list', (tester) async {
    await pump(tester, data: [web, db], width: 760);
    await tester.tap(find.text('Web North'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Connect selected (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'connections-compact-en');
  });
}

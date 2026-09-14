import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/x_connection_center.dart';

void main() {
  testWidgets('empty states translate while user group names remain verbatim', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final hosts = HostProvider(StorageService());
    await hosts.ready;
    await hosts.addGroup('收藏');
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(hosts.dispose);
    addTearDown(locale.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: hosts,
        child: ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (_, language, _) => MaterialApp(
            locale: language,
            localizationsDelegates: WayttyStrings.delegates,
            supportedLocales: WayttyStrings.supportedLocales,
            home: Scaffold(
              body: XConnectionCenter(
                onAdd: (_, _) {},
                onEdit: (_) {},
                onConnect: (_) async {},
                onImport: () {},
                onNewGroup: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No connections yet'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget); // User-authored folder.
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('No connections in Favorites'), findsOneWidget);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('No connections in “收藏”'), findsOneWidget);
    locale.value = const Locale('zh', 'CN');
    await tester.pumpAndSettle();
    expect(find.text('“收藏”中还没有连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

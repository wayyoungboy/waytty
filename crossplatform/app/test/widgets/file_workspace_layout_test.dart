import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/models/local_entry.dart';
import 'package:yourssh/providers/local_file_panel_provider.dart';
import 'package:yourssh/widgets/local_file_panel.dart';
import 'package:yourssh/widgets/file_tree_view.dart';

void main() {
  testWidgets('local tree fits the minimum sidebar width and selection works', (tester) async {
    final provider = LocalFilePanelProvider.atPath('/fixture')
      ..setEntriesForTest([LocalEntry(name: 'README.md', path: '/fixture/README.md',
        isDirectory: false, size: 24, modifiedAt: DateTime(2026), permissions: '-rw-r--r--')]);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'), supportedLocales: WayttyStrings.supportedLocales,
      localizationsDelegates: WayttyStrings.delegates,
      home: Scaffold(body: ChangeNotifierProvider.value(value: provider,
        child: SizedBox(width: 240, child: LocalFilePanel(provider: provider,
          treeCache: FileTreeCache<LocalEntry>()))))));
    await tester.pumpAndSettle();
    expect(find.text('README.md'), findsOneWidget);
    await tester.tap(find.text('README.md'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(provider.selectedEntries.single.name, 'README.md');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}

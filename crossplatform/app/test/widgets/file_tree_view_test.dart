import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/file_tree_view.dart';

void main() {
  testWidgets('lazy expansion, collapse, filter, errors and retry', (
    tester,
  ) async {
    final cache = FileTreeCache<String>();
    final calls = <String>[];
    bool fail = true;
    Widget app({String filter = ''}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          child: FileTreeView<String>(
            root: '/',
            revision: 1,
            entries: const ['/src', '/readme.txt'],
            cache: cache,
            pathOf: (e) => e,
            nameOf: (e) => e.split('/').last,
            isDirectory: (e) => e == '/src',
            filter: filter,
            listDirectory: (path) async {
              calls.add(path);
              if (fail) throw StateError('fixture denied');
              return ['/src/main.dart'];
            },
            onOpen: (_) {},
            onSelect: (_) {},
            isSelected: (_) => false,
            wrapEntry: (_, child) => child,
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    expect(calls, isEmpty);
    await tester.tap(find.byTooltip('Expand folder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fixture denied'), findsOneWidget);
    fail = false;
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);
    await tester.pumpWidget(app(filter: 'main'));
    expect(find.text('readme.txt'), findsNothing);
    expect(find.text('src'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse folder'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsNothing);
    await tester.tap(find.byTooltip('Expand folder'));
    await tester.pumpAndSettle();
    expect(calls, ['/src', '/src']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late directory replies cannot contaminate a new root', (
    tester,
  ) async {
    final cache = FileTreeCache<String>();
    final pending = Completer<List<String>>();
    Widget app(String root, int revision) => MaterialApp(
      home: Scaffold(
        body: FileTreeView<String>(
          root: root,
          revision: revision,
          entries: ['$root/dir'],
          cache: cache,
          pathOf: (e) => e,
          nameOf: (e) => e,
          isDirectory: (_) => true,
          listDirectory: (_) => pending.future,
          onOpen: (_) {},
          onSelect: (_) {},
          isSelected: (_) => false,
          wrapEntry: (_, child) => child,
        ),
      ),
    );
    await tester.pumpWidget(app('/old', 1));
    await tester.tap(find.byTooltip('Expand folder'));
    await tester.pump();
    await tester.pumpWidget(app('/new', 2));
    pending.complete(['/old/secret']);
    await tester.pumpAndSettle();
    expect(find.text('/old/secret'), findsNothing);
    expect(cache.children, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

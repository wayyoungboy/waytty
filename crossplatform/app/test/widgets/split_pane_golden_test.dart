import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/pane_tree.dart';

/// Renders a schematic of the recursive pane tree (no real PTY) and writes
/// PNGs under /workspace/split-shots for the PR.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Directory('/workspace/split-shots').createSync(recursive: true);
  });

  testWidgets('horizontal split schematic', (tester) async {
    const root = PaneBranch(
      id: 'b1',
      axis: SplitAxis.horizontal,
      ratio: 0.45,
      first: PaneLeaf(id: 'p1', sessionId: 's1'),
      second: PaneLeaf(id: 'p2', sessionId: 's2'),
    );
    await _pumpAndSave(tester, root, 'p1', 'split-horizontal.png');
  });

  testWidgets('vertical split schematic', (tester) async {
    const root = PaneBranch(
      id: 'b1',
      axis: SplitAxis.vertical,
      ratio: 0.55,
      first: PaneLeaf(id: 'p1', sessionId: 's1'),
      second: PaneLeaf(id: 'p2', sessionId: 's2'),
    );
    await _pumpAndSave(tester, root, 'p2', 'split-vertical.png');
  });

  testWidgets('nested L-shape schematic', (tester) async {
    const root = PaneBranch(
      id: 'b1',
      axis: SplitAxis.horizontal,
      ratio: 0.4,
      first: PaneLeaf(id: 'p1', sessionId: 's1'),
      second: PaneBranch(
        id: 'b2',
        axis: SplitAxis.vertical,
        ratio: 0.5,
        first: PaneLeaf(id: 'p2', sessionId: 's2'),
        second: PaneLeaf(id: 'p3', sessionId: 's3'),
      ),
    );
    await _pumpAndSave(tester, root, 'p3', 'split-nested.png');
  });
}

final _boundaryKey = GlobalKey();

Future<void> _pumpAndSave(
  WidgetTester tester,
  PaneNode root,
  String focusedPaneId,
  String filename,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 560));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: Center(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: SizedBox(
              width: 800,
              height: 500,
              child: _PaneSchematic(root: root, focusedPaneId: focusedPaneId),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(
    () => boundary.toImage(pixelRatio: 2),
  );
  final byteData = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('/workspace/split-shots/$filename')
      .writeAsBytesSync(byteData!.buffer.asUint8List());
}

class _PaneSchematic extends StatelessWidget {
  final PaneNode root;
  final String focusedPaneId;
  const _PaneSchematic({required this.root, required this.focusedPaneId});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF141414),
        child: _node(root),
      );

  Widget _node(PaneNode node) {
    return switch (node) {
      PaneLeaf leaf => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            border: Border.all(
              color: leaf.id == focusedPaneId
                  ? const Color(0xFF22C55E)
                  : const Color(0xFF404040),
              width: leaf.id == focusedPaneId ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Terminal ${leaf.sessionId}',
                style: TextStyle(
                  color: leaf.id == focusedPaneId
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFAAAAAA),
                  fontSize: 16,
                  fontFamily: 'monospace',
                ),
              ),
              if (leaf.id == focusedPaneId)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'focused',
                    style: TextStyle(color: Color(0xFF22C55E), fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      PaneBranch branch => LayoutBuilder(
          builder: (context, c) {
            final isRow = branch.axis == SplitAxis.horizontal;
            final max = (isRow ? c.maxWidth : c.maxHeight) - 4;
            final first = max * branch.ratio;
            final second = max - first;
            final children = <Widget>[
              SizedBox(
                width: isRow ? first : null,
                height: isRow ? null : first,
                child: _node(branch.first),
              ),
              ColoredBox(
                color: const Color(0xFF808080),
                child: SizedBox(
                  width: isRow ? 4 : double.infinity,
                  height: isRow ? double.infinity : 4,
                ),
              ),
              SizedBox(
                width: isRow ? second : null,
                height: isRow ? null : second,
                child: _node(branch.second),
              ),
            ];
            return isRow
                ? Row(children: children)
                : Column(children: children);
          },
        ),
    };
  }
}

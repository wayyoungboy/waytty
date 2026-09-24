import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/pane_tree.dart';

void main() {
  group('PaneTreeOps.split', () {
    test('splits a leaf into a branch with both sessions', () {
      const root = PaneLeaf(id: 'p1', sessionId: 's1');
      final next = PaneTreeOps.split(
        root: root,
        targetPaneId: 'p1',
        axis: SplitAxis.horizontal,
        newPaneId: 'p2',
        newSessionId: 's2',
        branchId: 'b1',
      );
      expect(next, isA<PaneBranch>());
      final branch = next as PaneBranch;
      expect(branch.axis, SplitAxis.horizontal);
      expect(branch.ratio, 0.5);
      expect(branch.sessionIds, ['s1', 's2']);
      expect(branch.leaves.map((l) => l.id), ['p1', 'p2']);
    });

    test('supports nested splits', () {
      var root = PaneTreeOps.split(
        root: const PaneLeaf(id: 'p1', sessionId: 's1'),
        targetPaneId: 'p1',
        axis: SplitAxis.horizontal,
        newPaneId: 'p2',
        newSessionId: 's2',
        branchId: 'b1',
      );
      root = PaneTreeOps.split(
        root: root,
        targetPaneId: 'p2',
        axis: SplitAxis.vertical,
        newPaneId: 'p3',
        newSessionId: 's3',
        branchId: 'b2',
      );
      expect(root.sessionIds, ['s1', 's2', 's3']);
      expect(root.leaves.length, 3);
    });
  });

  group('PaneTreeOps.close', () {
    test('closing one of two leaves returns the sibling', () {
      final root = PaneTreeOps.split(
        root: const PaneLeaf(id: 'p1', sessionId: 's1'),
        targetPaneId: 'p1',
        axis: SplitAxis.vertical,
        newPaneId: 'p2',
        newSessionId: 's2',
        branchId: 'b1',
      );
      final after = PaneTreeOps.close(root: root, paneId: 'p2');
      expect(after, isA<PaneLeaf>());
      expect((after as PaneLeaf).sessionId, 's1');
    });

    test('closing the last leaf returns null', () {
      const root = PaneLeaf(id: 'p1', sessionId: 's1');
      expect(PaneTreeOps.close(root: root, paneId: 'p1'), isNull);
    });

    test('closing nested leaf promotes sibling and preserves other branch', () {
      var root = PaneTreeOps.split(
        root: const PaneLeaf(id: 'p1', sessionId: 's1'),
        targetPaneId: 'p1',
        axis: SplitAxis.horizontal,
        newPaneId: 'p2',
        newSessionId: 's2',
        branchId: 'b1',
      );
      root = PaneTreeOps.split(
        root: root,
        targetPaneId: 'p2',
        axis: SplitAxis.vertical,
        newPaneId: 'p3',
        newSessionId: 's3',
        branchId: 'b2',
      );
      // Tree: H(p1, V(p2, p3)). Close p3 → H(p1, p2).
      final after = PaneTreeOps.close(root: root, paneId: 'p3')!;
      expect(after.sessionIds, ['s1', 's2']);
      expect(after, isA<PaneBranch>());
      expect((after as PaneBranch).second, isA<PaneLeaf>());
    });
  });

  group('PaneTreeOps.resize', () {
    test('clamps ratio to 0.1–0.9', () {
      final root = PaneTreeOps.split(
        root: const PaneLeaf(id: 'p1', sessionId: 's1'),
        targetPaneId: 'p1',
        axis: SplitAxis.horizontal,
        newPaneId: 'p2',
        newSessionId: 's2',
        branchId: 'b1',
      );
      final tiny = PaneTreeOps.resize(root: root, branchId: 'b1', ratio: 0.01);
      expect((tiny as PaneBranch).ratio, 0.1);
      final huge = PaneTreeOps.resize(root: root, branchId: 'b1', ratio: 0.99);
      expect((huge as PaneBranch).ratio, 0.9);
      final mid = PaneTreeOps.resize(root: root, branchId: 'b1', ratio: 0.33);
      expect((mid as PaneBranch).ratio, closeTo(0.33, 1e-9));
    });
  });

  group('PaneTreeOps.focusNeighbor', () {
    test('moves left/right across a horizontal split', () {
      final root = PaneTreeOps.split(
        root: const PaneLeaf(id: 'p1', sessionId: 's1'),
        targetPaneId: 'p1',
        axis: SplitAxis.horizontal,
        newPaneId: 'p2',
        newSessionId: 's2',
        branchId: 'b1',
      );
      expect(
        PaneTreeOps.focusNeighbor(
          root: root,
          fromPaneId: 'p1',
          direction: 'right',
        )?.id,
        'p2',
      );
      expect(
        PaneTreeOps.focusNeighbor(
          root: root,
          fromPaneId: 'p2',
          direction: 'left',
        )?.id,
        'p1',
      );
    });

    test('moves up/down across a vertical split', () {
      final root = PaneTreeOps.split(
        root: const PaneLeaf(id: 'p1', sessionId: 's1'),
        targetPaneId: 'p1',
        axis: SplitAxis.vertical,
        newPaneId: 'p2',
        newSessionId: 's2',
        branchId: 'b1',
      );
      expect(
        PaneTreeOps.focusNeighbor(
          root: root,
          fromPaneId: 'p1',
          direction: 'down',
        )?.id,
        'p2',
      );
    });
  });

  test('toJson/fromJson round-trip', () {
    var root = PaneTreeOps.split(
      root: const PaneLeaf(id: 'p1', sessionId: 's1'),
      targetPaneId: 'p1',
      axis: SplitAxis.horizontal,
      newPaneId: 'p2',
      newSessionId: 's2',
      branchId: 'b1',
      ratio: 0.4,
    );
    final restored = PaneNode.fromJson(root.toJson());
    expect(restored, root);
  });
}

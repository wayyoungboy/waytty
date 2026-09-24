import 'package:flutter/foundation.dart';

/// Direction of a split: [horizontal] places children left|right;
/// [vertical] places them top|bottom.
enum SplitAxis { horizontal, vertical }

/// Recursive pane tree. Leaves host a terminal [sessionId]; branches split
/// along [SplitAxis] with a [ratio] for the first child's share of space.
@immutable
sealed class PaneNode {
  const PaneNode();

  String get id;

  /// Session ids hosted by every leaf under this node, depth-first.
  List<String> get sessionIds;

  /// Every leaf under this node, depth-first.
  List<PaneLeaf> get leaves;

  PaneLeaf? leafById(String paneId);
  PaneLeaf? leafBySessionId(String sessionId);
  PaneBranch? branchById(String branchId);

  /// Replace the subtree rooted at [paneId] with [replacement].
  PaneNode replace(String paneId, PaneNode replacement);

  Map<String, dynamic> toJson();

  factory PaneNode.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'branch') return PaneBranch.fromJson(json);
    return PaneLeaf.fromJson(json);
  }
}

@immutable
class PaneLeaf extends PaneNode {
  @override
  final String id;
  final String sessionId;

  const PaneLeaf({required this.id, required this.sessionId});

  @override
  List<String> get sessionIds => [sessionId];

  @override
  List<PaneLeaf> get leaves => [this];

  @override
  PaneLeaf? leafById(String paneId) => paneId == id ? this : null;

  @override
  PaneLeaf? leafBySessionId(String sid) => sid == sessionId ? this : null;

  @override
  PaneBranch? branchById(String branchId) => null;

  @override
  PaneNode replace(String paneId, PaneNode replacement) =>
      paneId == id ? replacement : this;

  PaneLeaf copyWith({String? id, String? sessionId}) => PaneLeaf(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'leaf',
        'id': id,
        'sessionId': sessionId,
      };

  factory PaneLeaf.fromJson(Map<String, dynamic> json) => PaneLeaf(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is PaneLeaf && other.id == id && other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(id, sessionId);
}

@immutable
class PaneBranch extends PaneNode {
  @override
  final String id;
  final SplitAxis axis;

  /// Fraction of space given to [first] (clamped to 0.1–0.9 on write).
  final double ratio;
  final PaneNode first;
  final PaneNode second;

  const PaneBranch({
    required this.id,
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
  });

  @override
  List<String> get sessionIds => [...first.sessionIds, ...second.sessionIds];

  @override
  List<PaneLeaf> get leaves => [...first.leaves, ...second.leaves];

  @override
  PaneLeaf? leafById(String paneId) =>
      first.leafById(paneId) ?? second.leafById(paneId);

  @override
  PaneLeaf? leafBySessionId(String sid) =>
      first.leafBySessionId(sid) ?? second.leafBySessionId(sid);

  @override
  PaneBranch? branchById(String branchId) {
    if (branchId == id) return this;
    return first.branchById(branchId) ?? second.branchById(branchId);
  }

  @override
  PaneNode replace(String paneId, PaneNode replacement) {
    if (paneId == id) return replacement;
    return PaneBranch(
      id: id,
      axis: axis,
      ratio: ratio,
      first: first.replace(paneId, replacement),
      second: second.replace(paneId, replacement),
    );
  }

  PaneBranch copyWith({
    String? id,
    SplitAxis? axis,
    double? ratio,
    PaneNode? first,
    PaneNode? second,
  }) =>
      PaneBranch(
        id: id ?? this.id,
        axis: axis ?? this.axis,
        ratio: ratio ?? this.ratio,
        first: first ?? this.first,
        second: second ?? this.second,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'branch',
        'id': id,
        'axis': axis.name,
        'ratio': ratio,
        'first': first.toJson(),
        'second': second.toJson(),
      };

  factory PaneBranch.fromJson(Map<String, dynamic> json) => PaneBranch(
        id: json['id'] as String,
        axis: SplitAxis.values.firstWhere(
          (a) => a.name == json['axis'],
          orElse: () => SplitAxis.horizontal,
        ),
        ratio: (json['ratio'] as num?)?.toDouble() ?? 0.5,
        first: PaneNode.fromJson(json['first'] as Map<String, dynamic>),
        second: PaneNode.fromJson(json['second'] as Map<String, dynamic>),
      );

  @override
  bool operator ==(Object other) =>
      other is PaneBranch &&
      other.id == id &&
      other.axis == axis &&
      other.ratio == ratio &&
      other.first == first &&
      other.second == second;

  @override
  int get hashCode => Object.hash(id, axis, ratio, first, second);
}

/// Pure helpers for mutating a pane tree. All return a new root.
class PaneTreeOps {
  PaneTreeOps._();

  static const minRatio = 0.1;
  static const maxRatio = 0.9;

  static double clampRatio(double r) => r.clamp(minRatio, maxRatio);

  /// Split [targetPaneId] along [axis], placing the existing leaf as
  /// [first] and a new leaf for [newSessionId] as [second].
  static PaneNode split({
    required PaneNode root,
    required String targetPaneId,
    required SplitAxis axis,
    required String newPaneId,
    required String newSessionId,
    required String branchId,
    double ratio = 0.5,
  }) {
    final target = root.leafById(targetPaneId);
    if (target == null) return root;
    final branch = PaneBranch(
      id: branchId,
      axis: axis,
      ratio: clampRatio(ratio),
      first: target,
      second: PaneLeaf(id: newPaneId, sessionId: newSessionId),
    );
    return root.replace(targetPaneId, branch);
  }

  /// Remove the leaf [paneId]. Returns the new root, or `null` when the
  /// last leaf was closed. The sibling expands to fill the space.
  static PaneNode? close({
    required PaneNode root,
    required String paneId,
  }) {
    if (root is PaneLeaf) {
      return root.id == paneId ? null : root;
    }
    return _closeIn(root as PaneBranch, paneId);
  }

  static PaneNode? _closeIn(PaneBranch branch, String paneId) {
    if (branch.first is PaneLeaf && (branch.first as PaneLeaf).id == paneId) {
      return branch.second;
    }
    if (branch.second is PaneLeaf && (branch.second as PaneLeaf).id == paneId) {
      return branch.first;
    }
    final newFirst = branch.first is PaneBranch
        ? _closeIn(branch.first as PaneBranch, paneId)
        : branch.first;
    final newSecond = branch.second is PaneBranch
        ? _closeIn(branch.second as PaneBranch, paneId)
        : branch.second;
    // A null child means that entire subtree collapsed — promote sibling.
    if (newFirst == null) return newSecond;
    if (newSecond == null) return newFirst;
    if (identical(newFirst, branch.first) &&
        identical(newSecond, branch.second)) {
      return branch; // unchanged
    }
    return branch.copyWith(first: newFirst, second: newSecond);
  }

  /// Update the ratio of [branchId].
  static PaneNode resize({
    required PaneNode root,
    required String branchId,
    required double ratio,
  }) {
    final branch = root.branchById(branchId);
    if (branch == null) return root;
    return root.replace(
      branchId,
      branch.copyWith(ratio: clampRatio(ratio)),
    );
  }

  /// Nearest leaf in [direction] from [fromPaneId], or null.
  /// [direction]: left/right/up/down.
  static PaneLeaf? focusNeighbor({
    required PaneNode root,
    required String fromPaneId,
    required String direction,
  }) {
    final leaves = root.leaves;
    final idx = leaves.indexWhere((l) => l.id == fromPaneId);
    if (idx < 0) return null;

    // Walk ancestors to find a branch whose axis matches the move, then
    // pick the nearest leaf on the far side.
    return _neighborWalk(root, fromPaneId, direction) ??
        _fallbackLinear(leaves, idx, direction);
  }

  static PaneLeaf? _neighborWalk(
    PaneNode node,
    String fromPaneId,
    String direction,
  ) {
    if (node is! PaneBranch) return null;
    final inFirst = node.first.leafById(fromPaneId) != null;
    final inSecond = node.second.leafById(fromPaneId) != null;
    if (!inFirst && !inSecond) return null;

    final wantsFirst = direction == 'left' || direction == 'up';
    final axisMatches = (direction == 'left' || direction == 'right')
        ? node.axis == SplitAxis.horizontal
        : node.axis == SplitAxis.vertical;

    if (axisMatches) {
      if (inFirst && !wantsFirst) {
        return node.second.leaves.first;
      }
      if (inSecond && wantsFirst) {
        return node.first.leaves.last;
      }
    }

    // Recurse into the child that contains the focus.
    final child = inFirst ? node.first : node.second;
    return _neighborWalk(child, fromPaneId, direction);
  }

  static PaneLeaf? _fallbackLinear(
    List<PaneLeaf> leaves,
    int idx,
    String direction,
  ) {
    if (direction == 'right' || direction == 'down') {
      return idx + 1 < leaves.length ? leaves[idx + 1] : null;
    }
    return idx - 1 >= 0 ? leaves[idx - 1] : null;
  }
}

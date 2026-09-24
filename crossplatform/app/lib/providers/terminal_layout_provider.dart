// app/lib/providers/terminal_layout_provider.dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/pane_tree.dart';

/// Legacy fixed layouts kept for workspace snapshot compatibility.
/// New UI uses the recursive [PaneNode] tree via [TerminalGroup].
enum SplitLayout { single, horizontal, vertical, quad }

/// Which right-side workspace panel is open. Only one at a time.
enum SidePanel { none, snippets, terminalConfig, monitor }

/// One top-level tab's terminal workspace: a recursive pane tree plus focus.
class TerminalGroup {
  final String id;
  PaneNode root;
  String focusedPaneId;

  TerminalGroup({
    required this.id,
    required this.root,
    required this.focusedPaneId,
  });

  int get paneCount => root.leaves.length;

  List<String> get sessionIds => root.sessionIds;

  PaneLeaf? get focusedLeaf => root.leafById(focusedPaneId);
}

class TerminalLayoutProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  bool _broadcastEnabled = false;
  bool _filesVisible = true;
  double _filesWidth = 300;
  bool _inputBarVisible = false;
  SidePanel _sidePanel = SidePanel.none;

  /// groupId → group. groupId equals the first session id that opened the tab.
  final Map<String, TerminalGroup> _groups = {};

  /// sessionId → groupId for every pane-hosted session (including the root).
  final Map<String, String> _sessionToGroup = {};

  /// Active group follows the focused/active terminal session.
  String? _activeGroupId;

  /// Legacy layout value mirrored for workspace snapshot round-trip.
  SplitLayout _legacyLayout = SplitLayout.single;

  bool get filesVisible => _filesVisible;
  double get filesWidth => _filesWidth;

  void toggleFiles() {
    _filesVisible = !_filesVisible;
    notifyListeners();
  }

  void resizeFiles(double width) {
    _filesWidth = width.clamp(240, 520);
    notifyListeners();
  }

  bool get broadcastEnabled => _broadcastEnabled;
  bool get inputBarVisible => _inputBarVisible;
  SidePanel get sidePanel => _sidePanel;
  bool get snippetsPanelVisible => _sidePanel == SidePanel.snippets;
  bool get configPanelVisible => _sidePanel == SidePanel.terminalConfig;
  bool get monitorPanelVisible => _sidePanel == SidePanel.monitor;

  /// Legacy getter — derived from the active group's tree shape when possible.
  SplitLayout get layout {
    final g = activeGroup;
    if (g == null) return _legacyLayout;
    if (g.paneCount <= 1) return SplitLayout.single;
    final root = g.root;
    if (root is PaneBranch &&
        root.first is PaneLeaf &&
        root.second is PaneLeaf) {
      return root.axis == SplitAxis.horizontal
          ? SplitLayout.horizontal
          : SplitLayout.vertical;
    }
    // Quad or deeper nesting — report quad for snapshot compat.
    if (g.paneCount >= 4) return SplitLayout.quad;
    return root is PaneBranch && root.axis == SplitAxis.horizontal
        ? SplitLayout.horizontal
        : SplitLayout.vertical;
  }

  int get paneCount => activeGroup?.paneCount ?? 1;

  TerminalGroup? get activeGroup =>
      _activeGroupId == null ? null : _groups[_activeGroupId];

  TerminalGroup? groupForSession(String sessionId) {
    final gid = _sessionToGroup[sessionId];
    return gid == null ? null : _groups[gid];
  }

  /// Sessions that should appear as top tabs (group representatives +
  /// non-grouped sessions). Child panes of a split are hidden.
  bool isTabVisible(String sessionId) {
    final gid = _sessionToGroup[sessionId];
    if (gid == null) return true; // not tracked → show (RDP/serial/etc.)
    return gid == sessionId; // group id == root session id
  }

  /// Group ids (root session ids) currently tracked.
  Iterable<String> get groupIds => _groups.keys;

  /// Ensure [sessionId] has a singleton group. No-op if already grouped.
  /// Set [notify] false when calling from build (first-frame bind).
  void ensureGroup(String sessionId, {bool notify = true}) {
    if (_sessionToGroup.containsKey(sessionId)) return;
    final paneId = _uuid.v4();
    final leaf = PaneLeaf(id: paneId, sessionId: sessionId);
    _groups[sessionId] = TerminalGroup(
      id: sessionId,
      root: leaf,
      focusedPaneId: paneId,
    );
    _sessionToGroup[sessionId] = sessionId;
    _activeGroupId ??= sessionId;
    if (notify) notifyListeners();
  }

  /// Focus the group that owns [sessionId] and the leaf hosting it.
  void activateSession(String sessionId) {
    ensureGroup(sessionId);
    final gid = _sessionToGroup[sessionId];
    if (gid == null) return;
    final group = _groups[gid]!;
    final leaf = group.root.leafBySessionId(sessionId);
    final focusId = leaf?.id ?? group.focusedPaneId;
    if (_activeGroupId == gid && group.focusedPaneId == focusId) return;
    _activeGroupId = gid;
    group.focusedPaneId = focusId;
    notifyListeners();
  }

  /// Split the focused pane of the active group. [newSessionId] must already
  /// exist in SessionProvider. Returns the new pane id, or null on failure.
  String? splitFocused({
    required SplitAxis axis,
    required String newSessionId,
  }) {
    final group = activeGroup;
    if (group == null) return null;
    // openSibling may have briefly registered the new session as its own
    // singleton group via ensureGroup — fold it back into this group.
    final orphanGid = _sessionToGroup[newSessionId];
    if (orphanGid != null && orphanGid != group.id) {
      _groups.remove(orphanGid);
      _sessionToGroup.remove(newSessionId);
    }
    final newPaneId = _uuid.v4();
    final branchId = _uuid.v4();
    group.root = PaneTreeOps.split(
      root: group.root,
      targetPaneId: group.focusedPaneId,
      axis: axis,
      newPaneId: newPaneId,
      newSessionId: newSessionId,
      branchId: branchId,
    );
    _sessionToGroup[newSessionId] = group.id;
    group.focusedPaneId = newPaneId;
    _legacyLayout = axis == SplitAxis.horizontal
        ? SplitLayout.horizontal
        : SplitLayout.vertical;
    notifyListeners();
    return newPaneId;
  }

  /// Close the focused pane. Returns the closed session id (caller should
  /// tear it down), or null when the group had only one pane (caller should
  /// close the whole tab instead).
  String? closeFocusedPane() {
    final group = activeGroup;
    if (group == null) return null;
    if (group.paneCount <= 1) return null; // signal: close whole tab

    final leaf = group.focusedLeaf;
    if (leaf == null) return null;
    final closedSessionId = leaf.sessionId;
    final newRoot = PaneTreeOps.close(root: group.root, paneId: leaf.id);
    if (newRoot == null) return null;

    group.root = newRoot;
    _sessionToGroup.remove(closedSessionId);
    // Focus a remaining leaf — prefer the first.
    group.focusedPaneId = newRoot.leaves.first.id;
    _legacyLayout =
        group.paneCount <= 1 ? SplitLayout.single : _legacyLayout;
    notifyListeners();
    return closedSessionId;
  }

  /// Close an arbitrary pane by id within the active group.
  String? closePane(String paneId) {
    final group = activeGroup;
    if (group == null) return null;
    final leaf = group.root.leafById(paneId);
    if (leaf == null) return null;
    if (group.paneCount <= 1) return null;

    final closedSessionId = leaf.sessionId;
    final newRoot = PaneTreeOps.close(root: group.root, paneId: paneId);
    if (newRoot == null) return null;
    group.root = newRoot;
    _sessionToGroup.remove(closedSessionId);
    if (group.focusedPaneId == paneId) {
      group.focusedPaneId = newRoot.leaves.first.id;
    }
    notifyListeners();
    return closedSessionId;
  }

  /// Drop an entire group and unmap its sessions (caller closes sessions).
  List<String> removeGroup(String groupId) {
    final group = _groups.remove(groupId);
    if (group == null) return const [];
    final ids = List<String>.from(group.sessionIds);
    for (final sid in ids) {
      _sessionToGroup.remove(sid);
    }
    if (_activeGroupId == groupId) {
      _activeGroupId = _groups.keys.firstOrNull;
    }
    notifyListeners();
    return ids;
  }

  /// Drop a session from whatever group it belongs to (e.g. external close).
  void detachSession(String sessionId) {
    final gid = _sessionToGroup[sessionId];
    if (gid == null) return;
    final group = _groups[gid];
    if (group == null) {
      _sessionToGroup.remove(sessionId);
      return;
    }
    if (group.id == sessionId && group.paneCount == 1) {
      // Closing the tab root of a singleton group.
      removeGroup(gid);
      return;
    }
    final leaf = group.root.leafBySessionId(sessionId);
    if (leaf == null) {
      _sessionToGroup.remove(sessionId);
      return;
    }
    final newRoot = PaneTreeOps.close(root: group.root, paneId: leaf.id);
    _sessionToGroup.remove(sessionId);
    if (newRoot == null) {
      _groups.remove(gid);
      if (_activeGroupId == gid) _activeGroupId = _groups.keys.firstOrNull;
    } else {
      group.root = newRoot;
      if (group.focusedPaneId == leaf.id) {
        group.focusedPaneId = newRoot.leaves.first.id;
      }
      // If we closed the root session id, re-key is intentionally NOT done —
      // group.id stays as the original tab id so isTabVisible keeps working
      // for the (now closed) root. Tabs should close the whole group instead.
    }
    notifyListeners();
  }

  void focusPane(String paneId) {
    final group = activeGroup;
    if (group == null) return;
    if (group.root.leafById(paneId) == null) return;
    if (group.focusedPaneId == paneId) return;
    group.focusedPaneId = paneId;
    notifyListeners();
  }

  /// Move focus to a neighboring pane. Returns the newly focused session id.
  String? focusNeighbor(String direction) {
    final group = activeGroup;
    if (group == null) return null;
    final next = PaneTreeOps.focusNeighbor(
      root: group.root,
      fromPaneId: group.focusedPaneId,
      direction: direction,
    );
    if (next == null) return null;
    group.focusedPaneId = next.id;
    notifyListeners();
    return next.sessionId;
  }

  void resizeBranch(String branchId, double ratio) {
    final group = activeGroup;
    if (group == null) return;
    group.root = PaneTreeOps.resize(
      root: group.root,
      branchId: branchId,
      ratio: ratio,
    );
    notifyListeners();
  }

  /// Legacy API used by workspace restore + old tests. Builds a shallow
  /// multi-pane tree from [sessionIds] (already-open sessions) under a
  /// synthetic group keyed by the first id.
  void setLayout(SplitLayout layout, {List<String>? sessionIds}) {
    _legacyLayout = layout;
    final ids = sessionIds;
    if (ids == null || ids.isEmpty) {
      notifyListeners();
      return;
    }
    // Rebuild active group from the provided sessions.
    final rootId = ids.first;
    PaneNode tree;
    switch (layout) {
      case SplitLayout.single:
        tree = PaneLeaf(id: _uuid.v4(), sessionId: ids[0]);
      case SplitLayout.horizontal:
      case SplitLayout.vertical:
        final a = PaneLeaf(id: _uuid.v4(), sessionId: ids[0]);
        final b = PaneLeaf(
          id: _uuid.v4(),
          sessionId: ids.length > 1 ? ids[1] : ids[0],
        );
        tree = PaneBranch(
          id: _uuid.v4(),
          axis: layout == SplitLayout.horizontal
              ? SplitAxis.horizontal
              : SplitAxis.vertical,
          ratio: 0.5,
          first: a,
          second: b,
        );
      case SplitLayout.quad:
        PaneNode leaf(int i) => PaneLeaf(
              id: _uuid.v4(),
              sessionId: ids[i.clamp(0, ids.length - 1)],
            );
        tree = PaneBranch(
          id: _uuid.v4(),
          axis: SplitAxis.vertical,
          ratio: 0.5,
          first: PaneBranch(
            id: _uuid.v4(),
            axis: SplitAxis.horizontal,
            ratio: 0.5,
            first: leaf(0),
            second: leaf(1),
          ),
          second: PaneBranch(
            id: _uuid.v4(),
            axis: SplitAxis.horizontal,
            ratio: 0.5,
            first: leaf(2),
            second: leaf(3),
          ),
        );
    }
    // Clear prior mappings for these sessions.
    for (final sid in ids) {
      final old = _sessionToGroup.remove(sid);
      if (old != null && old != rootId) {
        _groups.remove(old);
      }
    }
    _groups[rootId] = TerminalGroup(
      id: rootId,
      root: tree,
      focusedPaneId: tree.leaves.first.id,
    );
    for (final sid in tree.sessionIds) {
      _sessionToGroup[sid] = rootId;
    }
    _activeGroupId = rootId;
    notifyListeners();
  }

  void toggleBroadcast() {
    _broadcastEnabled = !_broadcastEnabled;
    notifyListeners();
  }

  void toggleInputBar() {
    _inputBarVisible = !_inputBarVisible;
    notifyListeners();
  }

  /// Toggles [panel]: opens it, or closes it if already open.
  /// Opening one panel replaces whichever other panel was open.
  void toggleSidePanel(SidePanel panel) {
    _sidePanel = (_sidePanel == panel) ? SidePanel.none : panel;
    notifyListeners();
  }

  void toggleSnippetsPanel() => toggleSidePanel(SidePanel.snippets);

  /// Test/helper: wipe all groups.
  @visibleForTesting
  void debugReset() {
    _groups.clear();
    _sessionToGroup.clear();
    _activeGroupId = null;
    _legacyLayout = SplitLayout.single;
    notifyListeners();
  }
}

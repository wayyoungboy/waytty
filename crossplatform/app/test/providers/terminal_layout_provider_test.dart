// app/test/providers/terminal_layout_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/pane_tree.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';

void main() {
  test('default layout is single with no groups', () {
    final p = TerminalLayoutProvider();
    expect(p.layout, SplitLayout.single);
    expect(p.paneCount, 1);
  });

  test('ensureGroup creates a singleton pane tree', () {
    final p = TerminalLayoutProvider();
    p.ensureGroup('s1');
    expect(p.activeGroup?.paneCount, 1);
    expect(p.activeGroup?.sessionIds, ['s1']);
    expect(p.isTabVisible('s1'), isTrue);
  });

  test('splitFocused adds a pane and hides the sibling from the tab bar', () {
    final p = TerminalLayoutProvider();
    p.ensureGroup('s1');
    p.activateSession('s1');
    p.splitFocused(axis: SplitAxis.horizontal, newSessionId: 's2');
    expect(p.paneCount, 2);
    expect(p.isTabVisible('s1'), isTrue);
    expect(p.isTabVisible('s2'), isFalse);
    expect(p.layout, SplitLayout.horizontal);
  });

  test('closeFocusedPane expands the sibling', () {
    final p = TerminalLayoutProvider();
    p.ensureGroup('s1');
    p.splitFocused(axis: SplitAxis.vertical, newSessionId: 's2');
    expect(p.paneCount, 2);
    final closed = p.closeFocusedPane();
    expect(closed, 's2');
    expect(p.paneCount, 1);
    expect(p.isTabVisible('s1'), isTrue);
  });

  test('closeFocusedPane returns null for a singleton (close whole tab)', () {
    final p = TerminalLayoutProvider();
    p.ensureGroup('s1');
    expect(p.closeFocusedPane(), isNull);
  });

  test('resizeBranch updates ratio', () {
    final p = TerminalLayoutProvider();
    p.ensureGroup('s1');
    p.splitFocused(axis: SplitAxis.horizontal, newSessionId: 's2');
    final branchId = (p.activeGroup!.root as PaneBranch).id;
    p.resizeBranch(branchId, 0.25);
    expect((p.activeGroup!.root as PaneBranch).ratio, 0.25);
  });

  test('focusNeighbor moves focus and returns session id', () {
    final p = TerminalLayoutProvider();
    p.ensureGroup('s1');
    p.splitFocused(axis: SplitAxis.horizontal, newSessionId: 's2');
    // After split, focus is on s2.
    expect(p.activeGroup!.focusedLeaf!.sessionId, 's2');
    expect(p.focusNeighbor('left'), 's1');
    expect(p.activeGroup!.focusedLeaf!.sessionId, 's1');
  });

  test('nested split right then down', () {
    final p = TerminalLayoutProvider();
    p.ensureGroup('s1');
    p.splitFocused(axis: SplitAxis.horizontal, newSessionId: 's2');
    p.splitFocused(axis: SplitAxis.vertical, newSessionId: 's3');
    expect(p.paneCount, 3);
    expect(p.activeGroup!.sessionIds.toSet(), {'s1', 's2', 's3'});
  });

  test('broadcastEnabled defaults to false', () {
    final p = TerminalLayoutProvider();
    expect(p.broadcastEnabled, false);
  });

  test('toggleBroadcast flips flag', () {
    final p = TerminalLayoutProvider();
    p.toggleBroadcast();
    expect(p.broadcastEnabled, true);
    p.toggleBroadcast();
    expect(p.broadcastEnabled, false);
  });

  test('setLayout builds a shallow tree from session ids', () {
    final p = TerminalLayoutProvider();
    p.setLayout(SplitLayout.quad, sessionIds: ['a', 'b', 'c', 'd']);
    expect(p.paneCount, 4);
    expect(p.layout, SplitLayout.quad);
  });

  test('setLayout notifies listeners', () {
    final p = TerminalLayoutProvider();
    var notificationCount = 0;
    p.addListener(() => notificationCount++);
    p.setLayout(SplitLayout.horizontal, sessionIds: ['a', 'b']);
    expect(notificationCount, 1);
  });

  test('toggleBroadcast notifies listeners', () {
    final p = TerminalLayoutProvider();
    var notificationCount = 0;
    p.addListener(() => notificationCount++);
    p.toggleBroadcast();
    expect(notificationCount, 1);
  });

  test('snippetsPanelVisible defaults to false', () {
    final p = TerminalLayoutProvider();
    expect(p.snippetsPanelVisible, false);
  });

  test('toggleSnippetsPanel flips visibility', () {
    final p = TerminalLayoutProvider();
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, true);
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, false);
  });

  test('toggleSnippetsPanel notifies listeners', () {
    final p = TerminalLayoutProvider();
    var notificationCount = 0;
    p.addListener(() => notificationCount++);
    p.toggleSnippetsPanel();
    expect(notificationCount, 1);
  });

  test('sidePanel defaults to none', () {
    final p = TerminalLayoutProvider();
    expect(p.sidePanel, SidePanel.none);
    expect(p.configPanelVisible, false);
  });

  test('toggleSidePanel opens and closes the same panel', () {
    final p = TerminalLayoutProvider();
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(p.configPanelVisible, true);
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(p.configPanelVisible, false);
    expect(p.sidePanel, SidePanel.none);
  });

  test('opening config panel closes snippets panel', () {
    final p = TerminalLayoutProvider();
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, true);
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(p.configPanelVisible, true);
    expect(p.snippetsPanelVisible, false);
  });

  test('opening snippets panel closes config panel', () {
    final p = TerminalLayoutProvider();
    p.toggleSidePanel(SidePanel.terminalConfig);
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, true);
    expect(p.configPanelVisible, false);
  });

  test('toggleSidePanel notifies listeners', () {
    final p = TerminalLayoutProvider();
    var notificationCount = 0;
    p.addListener(() => notificationCount++);
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(notificationCount, 1);
  });

  test('files are independent from the right panel and width is bounded', () {
    final p = TerminalLayoutProvider();
    expect(p.filesVisible, isTrue);
    p.toggleSidePanel(SidePanel.monitor);
    p.toggleFiles();
    expect(p.monitorPanelVisible, isTrue);
    expect(p.filesVisible, isFalse);
    p.toggleFiles();
    expect(p.filesVisible, isTrue);
    p.resizeFiles(100);
    expect(p.filesWidth, 240);
    p.resizeFiles(999);
    expect(p.filesWidth, 520);
  });

  test('removeGroup returns all session ids', () {
    final p = TerminalLayoutProvider();
    p.ensureGroup('s1');
    p.splitFocused(axis: SplitAxis.horizontal, newSessionId: 's2');
    final ids = p.removeGroup('s1');
    expect(ids.toSet(), {'s1', 's2'});
    expect(p.activeGroup, isNull);
  });
}

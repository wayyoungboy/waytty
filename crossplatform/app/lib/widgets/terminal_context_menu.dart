import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../models/pane_tree.dart';
import '../providers/session_provider.dart';
import '../providers/terminal_layout_provider.dart';
import '../util/terminal_split_actions.dart';

/// Actions offered by the terminal right-click menu (issue #43 + split panes).
enum TerminalMenuAction {
  copy,
  paste,
  selectAll,
  resetTerminal,
  splitRight,
  splitDown,
  closePane,
}

/// Shows the Copy / Paste / Select All / Split / Close context menu for a
/// terminal at [globalPosition] and performs the chosen action.
///
/// Shared by the SSH, local, and telnet terminal panes.
Future<void> showTerminalContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required Terminal terminal,
  required TerminalController controller,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  final action = await showMenu<TerminalMenuAction>(
    context: context,
    position: RelativeRect.fromSize(
      globalPosition & Size.zero,
      overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: TerminalMenuAction.copy,
        enabled: controller.selection != null,
        height: 36,
        child: const LText("Copy"),
      ),
      PopupMenuItem(
        value: TerminalMenuAction.paste,
        height: 36,
        child: const LText("Paste"),
      ),
      PopupMenuItem(
        value: TerminalMenuAction.selectAll,
        height: 36,
        child: const LText("Select All"),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: TerminalMenuAction.splitRight,
        height: 36,
        child: const LText("Split Right"),
      ),
      PopupMenuItem(
        value: TerminalMenuAction.splitDown,
        height: 36,
        child: const LText("Split Down"),
      ),
      PopupMenuItem(
        value: TerminalMenuAction.closePane,
        height: 36,
        child: const LText("Close Pane"),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: TerminalMenuAction.resetTerminal,
        height: 36,
        child: const LText("Reset Terminal"),
      ),
    ],
  );

  // The menu (and the clipboard fetch below) are async — the pane that
  // spawned us may have been disposed in the meantime (session drop, hotkey
  // close). Its controller dies with it, so bail out.
  if (!context.mounted) return;

  switch (action) {
    case TerminalMenuAction.copy:
      await terminalCopySelection(terminal, controller);
    case TerminalMenuAction.paste:
      final text = await terminalClipboardText();
      if (!context.mounted) return;
      if (text != null) {
        terminalPasteText(terminal, controller, text);
      }
    case TerminalMenuAction.selectAll:
      terminalSelectAll(terminal, controller);
    case TerminalMenuAction.resetTerminal:
      terminal.recoverFromStuckState();
    case TerminalMenuAction.splitRight:
      await TerminalSplitActions.splitFocused(context, SplitAxis.horizontal);
    case TerminalMenuAction.splitDown:
      await TerminalSplitActions.splitFocused(context, SplitAxis.vertical);
    case TerminalMenuAction.closePane:
      _closePaneOrTab(context);
    case null:
      break;
  }
}

void _closePaneOrTab(BuildContext context) {
  try {
    if (TerminalSplitActions.closeFocusedPane(context)) return;
    // Singleton: close the whole group / session like Ctrl+W on a single pane.
    final layout = context.read<TerminalLayoutProvider>();
    final sessions = context.read<SessionProvider>();
    final active = sessions.activeSession;
    if (active == null) return;
    final group = layout.groupForSession(active.id);
    if (group != null) {
      final ids = layout.removeGroup(group.id);
      sessions.closeSessions(ids.isEmpty ? [active.id] : ids);
      return;
    }
    sessions.closeActive();
  } on ProviderNotFoundException {
    // Tests that only exercise clipboard paths.
  }
}

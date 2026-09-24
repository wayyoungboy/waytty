import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import '../models/pane_tree.dart';
import '../models/terminal_session.dart';
import '../providers/session_provider.dart';
import '../providers/terminal_layout_provider.dart';

/// Soft cap aligned with XTerminal WebGL guidance (~15 concurrent terminals).
const int kMaxTerminalSessions = 15;

/// Shared split / close-pane actions for hotkeys, toolbar, and context menus.
class TerminalSplitActions {
  TerminalSplitActions._();

  static int terminalCount(SessionProvider sessions) =>
      sessions.sessions.whereType<TerminalSession>().length;

  static bool atCap(SessionProvider sessions) =>
      terminalCount(sessions) >= kMaxTerminalSessions;

  static void showCapSnack(BuildContext context) {
    final msg = tr(
      context,
      LMessage(
        'Too many terminals open (max {0}). Close some panes or tabs first.',
        [kMaxTerminalSessions],
      ),
    );
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  static Future<bool> splitFocused(
    BuildContext context,
    SplitAxis axis,
  ) async {
    final layout = context.read<TerminalLayoutProvider>();
    final sessions = context.read<SessionProvider>();
    final active = sessions.activeSession;
    if (active is! TerminalSession) return false;
    if (atCap(sessions)) {
      showCapSnack(context);
      return false;
    }
    layout.ensureGroup(active.id);
    layout.activateSession(active.id);
    final focused = layout.activeGroup?.focusedLeaf;
    if (focused == null) return false;
    final newId = await sessions.openSiblingSession(focused.sessionId);
    if (!context.mounted || newId == null) return false;
    // Cap may have been hit inside openSiblingSession too.
    layout.splitFocused(axis: axis, newSessionId: newId);
    sessions.setActive(newId);
    layout.activateSession(newId);
    return true;
  }

  /// Close focused pane if the tab is split; otherwise false (caller closes tab).
  static bool closeFocusedPane(BuildContext context) {
    final layout = context.read<TerminalLayoutProvider>();
    final sessions = context.read<SessionProvider>();
    final group = layout.activeGroup;
    if (group == null || group.paneCount <= 1) return false;
    final closed = layout.closeFocusedPane();
    if (closed == null) return false;
    sessions.closeSession(closed);
    final focus = layout.activeGroup?.focusedLeaf;
    if (focus != null) sessions.setActive(focus.sessionId);
    return true;
  }
}

// app/lib/widgets/broadcast_toolbar.dart
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import '../providers/plugin_provider.dart';
import '../providers/terminal_layout_provider.dart';

class BroadcastToolbar extends StatelessWidget {
  final VoidCallback? onSplitRight;
  final VoidCallback? onSplitDown;
  final VoidCallback? onClosePane;

  const BroadcastToolbar({
    super.key,
    this.onSplitRight,
    this.onSplitDown,
    this.onClosePane,
  });

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<TerminalLayoutProvider>();
    final snippetsEnabled = context
        .watch<PluginProvider>()
        .isEnabled(YourSSHSnippetsPlugin.pluginId);
    final paneCount = layout.paneCount;

    return Container(
      height: 36,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _LayoutButton(
            icon: Icons.account_tree_outlined,
            tooltip: tr(context, 'File workspace'),
            selected: layout.filesVisible,
            onTap: layout.toggleFiles,
          ),
          const SizedBox(width: 8),
          const LText("Layout:", style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
          const SizedBox(width: 8),
          _LayoutButton(
            icon: Icons.vertical_split,
            tooltip: tr(context, "Split Right"),
            selected: false,
            onTap: () => onSplitRight?.call(),
          ),
          _LayoutButton(
            icon: Icons.horizontal_split,
            tooltip: tr(context, "Split Down"),
            selected: false,
            onTap: () => onSplitDown?.call(),
          ),
          _LayoutButton(
            icon: Icons.close,
            tooltip: tr(context, "Close Pane"),
            selected: false,
            onTap: () => onClosePane?.call(),
          ),
          const SizedBox(width: 8),
          if (paneCount > 1)
            LText(
              LMessage("{0} panes", [paneCount]),
              style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
            ),
          const SizedBox(width: 8),
          if (snippetsEnabled)
            _LayoutButton(
              icon: Icons.code,
              tooltip: tr(context, "Toggle Snippets Panel"),
              selected: layout.snippetsPanelVisible,
              onTap: layout.toggleSnippetsPanel,
            ),
          _LayoutButton(
            icon: Icons.tune,
            tooltip: tr(context, "Toggle Terminal Settings"),
            selected: layout.configPanelVisible,
            onTap: () => layout.toggleSidePanel(SidePanel.terminalConfig),
          ),
          TextButton.icon(
            onPressed: () => layout.toggleSidePanel(SidePanel.monitor),
            icon: const Icon(Icons.monitor_heart_outlined, size: 16),
            label: const LText('Monitor', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: layout.monitorPanelVisible
                  ? const Color(0xFF22C55E) : const Color(0xFFAAAAAA),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
          ),
          const Spacer(),
          if (paneCount > 1)
            InkWell(
              onTap: layout.toggleBroadcast,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: layout.broadcastEnabled
                      ? const Color(0xFF22C55E).withValues(alpha: 0.2)
                      : Colors.transparent,
                  border: Border.all(
                    color: layout.broadcastEnabled
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF2A2A2A),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cell_tower,
                      size: 14,
                      color: layout.broadcastEnabled
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF888888),
                    ),
                    const SizedBox(width: 4),
                    LText(
                      "Broadcast",
                      style: TextStyle(
                        fontSize: 12,
                        color: layout.broadcastEnabled
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF888888),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LayoutButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _LayoutButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: selected ? const Color(0xFF22C55E) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

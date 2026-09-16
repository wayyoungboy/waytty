import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_engine_provider.dart';
import '../providers/plugin_provider.dart';
import '../theme/app_theme.dart';
import 'plugin_consent_dialog.dart';
import 'plugin_console_screen.dart';

class PluginManagerScreen extends StatelessWidget {
  const PluginManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engineProvider = context.watch<PluginEngineProvider>();
    final pluginProvider = context.watch<PluginProvider>();
    final jsPlugins = engineProvider.loadedPlugins;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (engineProvider.pendingConsent != null)
            Card(
              color: AppColors.card,
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                leading: const Icon(Icons.extension, color: Colors.amber),
                title: LText(
                  LMessage("New plugin: {0}", [engineProvider.pendingConsent!.name]),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                subtitle: Text(
                  engineProvider.pendingConsent!.id,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                trailing: ElevatedButton(
                  onPressed: () => showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => PluginConsentDialog(
                        manifest: engineProvider.pendingConsent!),
                  ),
                  child: const LText("Review"),
                ),
              ),
            ),

          // Dart plugins
          const LText(
            "BUILT-IN PLUGINS",
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          if (pluginProvider.plugins.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LText(
                "No built-in plugins registered.",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ...pluginProvider.plugins.map((plugin) {
              final enabled = pluginProvider.isEnabled(plugin.id);
              return Card(
                color: AppColors.card,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(plugin.icon,
                      color: enabled
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      size: 20),
                  title: LText(
                    plugin.name,
                    style: TextStyle(
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: LText(
                    plugin.description,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: Switch(
                    value: enabled,
                    onChanged: (_) => pluginProvider.toggle(plugin.id),
                    activeThumbColor: AppColors.accent,
                  ),
                ),
              );
            }),

          const SizedBox(height: 16),

          // JS / script plugins
          const LText(
            "SCRIPT PLUGINS",
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          if (jsPlugins.isEmpty) ...[
            const LText(
              "No script plugins loaded.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const LText(
              "Drop a plugin folder into ~/.waytty/plugins/\nEach folder needs plugin.json + index.js. Hot-reloaded on change.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ] else ...[
            for (final manifest in jsPlugins)
              Card(
                color: AppColors.card,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.code,
                      color: AppColors.accent, size: 20),
                  title: Text(
                    manifest.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: LText(
                    LMessage("{0}  •  v{1}", [manifest.id, manifest.version]),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.terminal,
                        color: AppColors.textSecondary, size: 18),
                    tooltip: tr(context, "View logs"),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PluginConsoleScreen(pluginId: manifest.id),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            const LText(
              "Loaded from ~/.waytty/plugins/ — hot-reloaded on change.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

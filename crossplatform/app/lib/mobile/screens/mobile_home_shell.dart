import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../security/tofu_watcher.dart';
import '../services/host_reachability_probe.dart';
import '../widgets/mobile_tab_bar.dart';
import 'mobile_hosts_screen.dart';
import '../../screens/notes_screen.dart';
import 'mobile_keys_screen.dart';
import 'mobile_settings_screen.dart';
import 'mobile_snippets_screen.dart';

/// Bottom-navigation shell for the Android app.
/// Four tabs: Hosts · Snippets · Keys · Settings.
/// Tab bodies are temporary placeholders until tasks T8/T9 land.
class MobileHomeShell extends StatefulWidget {
  const MobileHomeShell({super.key});

  @override
  State<MobileHomeShell> createState() => _MobileHomeShellState();
}

class _MobileHomeShellState extends State<MobileHomeShell> {
  MobileTab _current = MobileTab.hosts;
  bool _notesSelected = false;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HostReachabilityProbe(),
      child: Scaffold(
        body: TofuWatcher(
          child: Row(children: [
            if (MediaQuery.sizeOf(context).width >= 900)
              NavigationRail(extended: MediaQuery.sizeOf(context).width >= 1200,
                selectedIndex: _notesSelected ? 4 : MobileTab.values.indexOf(_current),
                onDestinationSelected: (index) => setState(() {
                  _notesSelected = index == 4;
                  if (index < 4) _current = MobileTab.values[index];
                }),
                destinations: const [
                  NavigationRailDestination(icon: Icon(Icons.dns_outlined), label: LText("连接")),
                  NavigationRailDestination(icon: Icon(Icons.code), label: LText("快捷命令")),
                  NavigationRailDestination(icon: Icon(Icons.key), label: LText("密钥")),
                  NavigationRailDestination(icon: Icon(Icons.settings_outlined), label: LText("设置")),
                  NavigationRailDestination(icon: Icon(Icons.description_outlined), label: LText("笔记")),
                ]),
            Expanded(child: _notesSelected ? const NotesScreen() : IndexedStack(
            index: MobileTab.values.indexOf(_current),
            children: const [
              MobileHostsScreen(),
              MobileSnippetsScreen(),
              MobileKeysScreen(),
              MobileSettingsScreen(),
            ],
          )),
          ]),
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width >= 900 ? null : MobileTabBar(
          current: _current,
          onSelect: (tab) => setState(() { _notesSelected = false; _current = tab; }),
        ),
      ),
    );
  }
}

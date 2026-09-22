import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';

import 'mobile_bootstrap.dart';
import '../widgets/ssh_credentials_dialog.dart';
import 'screens/mobile_home_shell.dart';
import 'security/app_lock_gate.dart';
import 'theme/mobile_theme.dart';

/// Root widget for the Android build. Dark-only; uses [buildMobileTheme]
/// for the mobile-specific design language. Holds the [MobileBootstrap]
/// and exposes its providers to the tree.
class WayttyMobileApp extends StatefulWidget {
  const WayttyMobileApp({super.key});

  @override
  State<WayttyMobileApp> createState() => _WayttyMobileAppState();
}

class _WayttyMobileAppState extends State<WayttyMobileApp> {
  final _bootstrap = MobileBootstrap();
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    final prompts = ManualCredentialPrompts(() => _navigatorKey.currentContext,
      privateKeys: _bootstrap.storage.privateKeys,
      canSaveKey: (host) async => (await _bootstrap.storage.loadHosts()).any((h) => h.id == host.id),
    );
    _bootstrap.ssh.privateKeyEditor = prompts.replace;
    _bootstrap.ssh.credentialsPrompt = prompts.request;
    _bootstrap.ssh.proxyPasswordPrompt = prompts.requestProxy;
  }

  @override
  void dispose() {
    _bootstrap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: _bootstrap.providers,
      child: ValueListenableBuilder<Locale>(
        valueListenable: WayttyLanguage.instance,
        builder: (context, locale, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        locale: locale,
        supportedLocales: WayttyStrings.supportedLocales,
        localizationsDelegates: WayttyStrings.delegates,
        title: 'waytty',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: buildMobileTheme(),
        home: const AppLockGate(child: MobileHomeShell()),
        ),
      ),
    );
  }
}

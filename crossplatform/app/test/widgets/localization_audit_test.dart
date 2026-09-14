import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/plugins/plugin_registry.dart';
import 'package:yourssh/providers/plugin_engine_provider.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/widgets/plugin_manager_screen.dart';
import 'package:yourssh/widgets/workspace_side_panel.dart';
import 'package:yourssh/widgets/source_picker_dialog.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import 'package:yourssh/mobile/widgets/mobile_tab_bar.dart';
import 'package:yourssh_devops/yourssh_devops.dart';
import 'package:yourssh_devops/src/screens/devops_hub_screen.dart';
import 'package:yourssh_web_tools/yourssh_web_tools.dart';
import 'package:yourssh_web_tools/src/screens/web_tools_screen.dart';
import 'package:yourssh_web_tools/src/screens/utility_tools.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _BrowserPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _BrowserController(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _BrowserDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _BrowserWidget(params);
}

class _BrowserController extends PlatformWebViewController {
  _BrowserController(super.params) : super.implementation();
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
}

class _BrowserDelegate extends PlatformNavigationDelegate {
  _BrowserDelegate(super.params) : super.implementation();
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
}

class _BrowserWidget extends PlatformWebViewWidget {
  _BrowserWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _ScriptPlugins extends ChangeNotifier implements PluginEngineProvider {
  @override
  PluginManifest? get pendingConsent => null;
  @override
  List<PluginManifest> get loadedPlugins => const [
    PluginManifest(
      id: 'user.extension',
      name: 'Settings',
      version: '1.0.0',
      entry: 'index.js',
      minAppVersion: '1.0.0',
      permissions: {},
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => WebViewPlatform.instance = _BrowserPlatform());
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WayttyLanguage.instance.restore();
  });
  Widget app(Widget child) => ValueListenableBuilder<Locale>(
    valueListenable: WayttyLanguage.instance,
    builder: (_, locale, _) => MaterialApp(
      locale: locale,
      supportedLocales: WayttyStrings.supportedLocales,
      localizationsDelegates: WayttyStrings.delegates,
      home: Scaffold(body: child),
    ),
  );
  testWidgets(
    'built-in extension metadata switches languages; user metadata stays raw',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        app(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => PluginProvider(plugins: kRegisteredPlugins),
              ),
              ChangeNotifierProvider<PluginEngineProvider>(
                create: (_) => _ScriptPlugins(),
              ),
            ],
            child: const PluginManagerScreen(),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final label in [
        '快捷命令',
        '运维中心',
        'Web 工具',
        '保存并调用可复用的 Shell 命令。',
        '网络工具、S3 浏览器、局域网共享、邮件捕获、MCP 服务和 Cloudflare 隧道',
        '内嵌浏览器、HTTP 客户端和端口转发浏览器。',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Settings'), findsOneWidget);
      await WayttyLanguage.instance.select('en');
      await t.pumpAndSettle();
      for (final plugin in kRegisteredPlugins) {
        expect(find.text(plugin.name), findsOneWidget);
        expect(find.text(plugin.description), findsOneWidget);
      }
      expect(find.text('Settings'), findsOneWidget);
      await WayttyLanguage.instance.select('zh');
      await t.pumpAndSettle();
      expect(find.text('运维中心'), findsOneWidget);
    },
  );

  testWidgets('workspace title and close tooltip follow current locale', (
    t,
  ) async {
    await t.pumpWidget(
      app(
        WorkspaceSidePanel(
          title: 'Snippets',
          closeTooltip: 'Close snippets panel',
          onClose: () {},
          child: const SizedBox(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('快捷命令'), findsOneWidget);
    expect(find.byTooltip('关闭快捷命令面板'), findsOneWidget);
    await WayttyLanguage.instance.select('en');
    await t.pumpAndSettle();
    expect(find.text('Snippets'), findsOneWidget);
    expect(find.byTooltip('Close snippets panel'), findsOneWidget);
  });

  testWidgets('a host named Settings keeps its user-defined name', (t) async {
    await t.pumpWidget(
      app(
        SourcePickerDialog(
          hosts: [
            Host(label: 'Settings', host: 'example.com', username: 'user'),
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('本地'), findsOneWidget);
  });

  testWidgets('mobile navigation labels switch with the application locale', (
    t,
  ) async {
    await t.pumpWidget(
      app(MobileTabBar(current: MobileTab.hosts, onSelect: (_) {})),
    );
    await t.pumpAndSettle();
    expect(find.text('快捷命令'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    await WayttyLanguage.instance.select('en');
    await t.pumpAndSettle();
    expect(find.text('Snippets'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('DevOps navigation translates labels passed through helpers', (
    t,
  ) async {
    await t.pumpWidget(
      app(
        DevOpsHubScreen(
          config: const DevOpsPluginConfig(
            containersScreen: SizedBox(),
            networkToolsScreen: SizedBox(),
            cloudflareScreen: SizedBox(),
            mailCatcherScreen: SizedBox(),
            mcpServerScreen: SizedBox(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('网络工具'), findsOneWidget);
    expect(find.text('局域网共享'), findsOneWidget);
    await WayttyLanguage.instance.select('en');
    await t.pumpAndSettle();
    expect(find.text('Network Tools'), findsOneWidget);
    expect(find.text('LAN Share'), findsOneWidget);
  });

  testWidgets('Web tools translate tab labels', (t) async {
    final previous = WebViewPlatform.instance;
    WebViewPlatform.instance = _BrowserPlatform();
    addTearDown(() => WebViewPlatform.instance = previous);
    await t.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      app(
        WebToolsScreen(
          config: WebToolsPluginConfig(
            portForwardBrowserBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('HTTP 客户端'), findsOneWidget);
    expect(find.text('端口隧道'), findsOneWidget);
    await WayttyLanguage.instance.select('en');
    await t.pumpAndSettle();
    expect(find.text('HTTP Client'), findsOneWidget);
    expect(find.text('Port Tunnels'), findsOneWidget);
  });

  testWidgets(
    'utility errors are Chinese while decoded content stays verbatim',
    (t) async {
      await t.pumpWidget(app(const UtilityTools()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '%%%');
      await t.tap(find.text('解码'));
      await t.pumpAndSettle();
      expect(find.text('无效的 Base64'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'SW52YWxpZCBCYXNlNjQ=');
      await t.tap(find.text('解码'));
      await t.pumpAndSettle();
      expect(find.text('Invalid Base64'), findsOneWidget);
      expect(find.text('无效的 Base64'), findsNothing);
    },
  );
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/ai_provider_config.dart';
import 'package:yourssh/providers/ai_chat_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final calls = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      throw PlatformException(code: 'forbidden-keychain-access');
    });
  });
  tearDown(() {
    expect(calls, isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('restart never reloads API keys from preferences or keychain', () async {
    SharedPreferences.setMockInitialValues({'ai_api_key': 'legacy-key'});
    final first = AiChatProvider();
    await first.ready;
    expect(first.configured, isFalse);
    await first.setProviderConfig(AiProvider.openai, apiKey: 'fixture-key');
    expect(first.configs[AiProvider.openai]!.apiKey, 'fixture-key');
    first.dispose();
    final restarted = AiChatProvider();
    await restarted.ready;
    expect(restarted.configuredProviders, isEmpty);
    expect((await SharedPreferences.getInstance()).getString('ai_api_key'), 'legacy-key');
    restarted.dispose();
  });

  group('AiChatProvider', () {
    late AiChatProvider provider;

    setUp(() {
      provider = AiChatProvider();
    });

    tearDown(() => provider.dispose());

    test('starts unconfigured with no configs', () async {
      await Future.delayed(Duration.zero);
      expect(provider.configured, isFalse);
      expect(provider.configuredProviders, isEmpty);
      expect(provider.activeProvider, AiProvider.anthropic);
    });

    test('setProviderConfig stores key and uses default model', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.anthropic, apiKey: 'sk-ant-test');
      expect(provider.configured, isTrue);
      expect(provider.configs[AiProvider.anthropic]?.apiKey, 'sk-ant-test');
      expect(provider.configs[AiProvider.anthropic]?.model,
          AiChatProvider.presetModels[AiProvider.anthropic]!.first);
    });

    test('setProviderConfig updates model without changing key', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'sk-test');
      await provider.setProviderConfig(AiProvider.openai, model: 'gpt-4o');
      expect(provider.configs[AiProvider.openai]?.model, 'gpt-4o');
      expect(provider.configs[AiProvider.openai]?.apiKey, 'sk-test');
    });

    test('clearProviderConfig removes config', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'sk-test');
      await provider.clearProviderConfig(AiProvider.openai);
      expect(provider.configs[AiProvider.openai], isNull);
      expect(provider.configuredProviders, isNot(contains(AiProvider.openai)));
    });

    test('configuredProviders returns only providers with keys', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.anthropic, apiKey: 'sk-ant');
      await provider.setProviderConfig(AiProvider.gemini, apiKey: 'AIza-test');
      expect(provider.configuredProviders,
          containsAll([AiProvider.anthropic, AiProvider.gemini]));
      expect(provider.configuredProviders, isNot(contains(AiProvider.openai)));
    });

    test('setActiveProvider changes active provider', () async {
      await Future.delayed(Duration.zero);
      await provider.setActiveProvider(AiProvider.openai);
      expect(provider.activeProvider, AiProvider.openai);
    });

    test('clearProviderConfig on active provider switches to next configured', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.anthropic, apiKey: 'sk-ant');
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'sk-oai');
      await provider.setActiveProvider(AiProvider.anthropic);
      await provider.clearProviderConfig(AiProvider.anthropic);
      expect(provider.activeProvider, AiProvider.openai);
    });

    test('clearProviderConfig on last provider sets active to anthropic', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'sk-oai');
      await provider.setActiveProvider(AiProvider.openai);
      await provider.clearProviderConfig(AiProvider.openai);
      expect(provider.activeProvider, AiProvider.anthropic);
      expect(provider.configured, isFalse);
    });
  });
}

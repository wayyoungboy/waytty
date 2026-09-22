import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_provider_config.dart';
import '../services/ai_completion_service.dart';
import '../models/chat_message.dart';

class AiChatProvider extends ChangeNotifier {
  static const _systemPrompt =
      'You are an SSH command assistant embedded in an SSH client app. '
      'Help the user with shell commands, explain error messages, suggest fixes, and assist with DevOps tasks. '
      'Keep responses concise and practical. Use code blocks for commands.';

  static const _activeProviderPrefKey = 'ai_active_provider';

  static const Map<AiProvider, List<String>> presetModels = {
    AiProvider.anthropic: [
      'claude-haiku-4-5-20251001',
      'claude-sonnet-4-6',
      'claude-opus-4-7',
    ],
    AiProvider.openai: ['gpt-4o-mini', 'gpt-4o', 'o1-mini'],
    AiProvider.gemini: [
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-1.5-pro',
    ],
  };

  final Map<AiProvider, AiProviderConfig> _configs = {};
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  bool _disposed = false;
  int _requestEpoch = 0;
  AiCompletionService? _request;
  final AiCompletionService Function() _requestFactory;
  late final Future<void> ready;
  String? loadError;
  AiProvider _activeProvider = AiProvider.anthropic;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  Map<AiProvider, AiProviderConfig> get configs => Map.unmodifiable(_configs);
  AiProvider get activeProvider => _activeProvider;
  bool _isConfigured(AiProvider p) =>
      _configs[p]?.apiKey.isNotEmpty == true ||
      _configs[p]?.endpoint?.isNotEmpty == true;
  bool get configured => _isConfigured(_activeProvider);
  List<AiProvider> get configuredProviders =>
      AiProvider.values.where(_isConfigured).toList();

  AiChatProvider({
    AiCompletionService Function()? requestFactory,
  }) : _requestFactory = requestFactory ?? AiCompletionService.new {
    ready = _load().catchError((Object e) {
      loadError = '无法读取 AI 凭据：$e';
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final providerName = prefs.getString(_activeProviderPrefKey);
    if (providerName != null) {
      _activeProvider = AiProvider.values.firstWhere(
        (p) => p.name == providerName,
        orElse: () => AiProvider.anthropic,
      );
    }

    for (final p in AiProvider.values) {
      final model =
          prefs.getString('ai_config_${p.name}_model') ??
          presetModels[p]!.first;
      final endpoint = prefs.getString('ai_config_${p.name}_endpoint');
      if (endpoint?.isNotEmpty == true) {
        _configs[p] = AiProviderConfig(
          apiKey: '', // API keys must be entered for this app run.
          model: model,
          endpoint: endpoint,
        );
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setProviderConfig(
    AiProvider provider, {
    String? apiKey,
    String? model,
    String? endpoint,
  }) async {
    await ready;
    final current = _configs[provider];
    final newKey = apiKey ?? current?.apiKey ?? '';
    final newEndpoint = endpoint ?? current?.endpoint;
    if (newEndpoint != null && newEndpoint.isNotEmpty) {
      final uri = Uri.tryParse(newEndpoint);
      if (uri == null ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          !(uri.scheme == 'https' ||
              (uri.scheme == 'http' &&
                  {'127.0.0.1', 'localhost', '::1'}.contains(uri.host)))) {
        throw ArgumentError('请输入 HTTPS 地址，或本机 HTTP 地址');
      }
    }
    final newModel = model ?? current?.model ?? presetModels[provider]!.first;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_config_${provider.name}_model', newModel);
    if (newEndpoint != null) {
      await prefs.setString('ai_config_${provider.name}_endpoint', newEndpoint);
    }

    if (newKey.isNotEmpty || newEndpoint?.isNotEmpty == true) {
      _configs[provider] = AiProviderConfig(
        apiKey: newKey,
        model: newModel,
        endpoint: newEndpoint,
      );
    } else if (current != null) {
      _configs[provider] = AiProviderConfig(
        apiKey: current.apiKey,
        model: newModel,
        endpoint: newEndpoint,
      );
    }
    notifyListeners();
  }

  Future<void> clearProviderConfig(AiProvider provider) async {
    await ready;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_config_${provider.name}_model');
    await prefs.remove('ai_config_${provider.name}_endpoint');
    _configs.remove(provider);
    if (_activeProvider == provider) {
      _activeProvider = configuredProviders.firstOrNull ?? AiProvider.anthropic;
      await prefs.setString(_activeProviderPrefKey, _activeProvider.name);
    }
    notifyListeners();
  }

  Future<void> setActiveProvider(AiProvider provider) async {
    await ready;
    _activeProvider = provider;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProviderPrefKey, provider.name);
    notifyListeners();
  }

  void clear() {
    stop();
    _messages.clear();
    notifyListeners();
  }

  void stop() {
    _requestEpoch++;
    _request?.cancel();
    _request = null;
    _loading = false;
    if (_messages.isNotEmpty && _messages.last.isStreaming) {
      _messages[_messages.length - 1] = _messages.last.copyWith(
        isStreaming: false,
      );
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _configs.clear();
    super.dispose();
  }

  Future<void> send(String userMessage, {String? context}) async {
    await ready;
    if (_disposed || _loading || !configured || userMessage.trim().isEmpty) {
      return;
    }
    final provider = _activeProvider;
    final config = _configs[provider]!;
    final epoch = ++_requestEpoch;
    _messages.add(
      ChatMessage.user(
        context == null
            ? userMessage
            : 'Context:\n```\n$context\n```\n\n$userMessage',
      ),
    );
    final history = _messages
        .where(
          (m) => m.role != 'system' && !m.isStreaming && m.content.isNotEmpty,
        )
        .map((m) => m.toApiMap())
        .toList();
    final index = _messages.length;
    _messages.add(ChatMessage.assistant('', isStreaming: true));
    _loading = true;
    notifyListeners();
    final request = _requestFactory();
    _request = request;
    final output = StringBuffer();
    try {
      await for (final delta in request.generate(
        provider: provider,
        config: config,
        system: _systemPrompt,
        messages: history,
      )) {
        if (_disposed || epoch != _requestEpoch) return;
        output.write(delta);
        _messages[index] = _messages[index].copyWith(
          content: output.toString(),
        );
        notifyListeners();
      }
      if (_disposed || epoch != _requestEpoch) return;
      _messages[index] = _messages[index].copyWith(
        isStreaming: false,
        content: output.isEmpty ? '服务未返回文本，请检查模型和接口配置。' : output.toString(),
      );
    } catch (e) {
      if (_disposed || epoch != _requestEpoch) return;
      _messages[index] = _messages[index].copyWith(
        isStreaming: false,
        content: '${output.toString()}\n请求失败：$e',
      );
    } finally {
      request.cancel();
      if (!_disposed && epoch == _requestEpoch) {
        _request = null;
        _loading = false;
        notifyListeners();
      }
    }
  }
}

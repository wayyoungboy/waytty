import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_provider_config.dart';

/// One cancellable request. Transport is shared by desktop and tablet clients.
class AiCompletionService {
  AiCompletionService({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _client.close();
  }

  Stream<String> generate({
    required AiProvider provider,
    required AiProviderConfig config,
    required String system,
    required List<Map<String, String>> messages,
  }) async* {
    final custom = config.endpoint;
    final defaultUrl = switch (provider) {
      AiProvider.openai => 'https://api.openai.com/v1/chat/completions',
      AiProvider.anthropic => 'https://api.anthropic.com/v1/messages',
      AiProvider.gemini =>
        'https://generativelanguage.googleapis.com/v1beta/models/${Uri.encodeComponent(config.model)}:streamGenerateContent?alt=sse',
    };
    final uri = Uri.parse(custom?.isNotEmpty == true ? custom! : defaultUrl);
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['content-type'] = 'application/json';
    switch (provider) {
      case AiProvider.openai:
        if (config.apiKey.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer ${config.apiKey}';
        }
        request.body = jsonEncode({
          'model': config.model,
          'stream': true,
          'messages': [
            {'role': 'system', 'content': system},
            ...messages,
          ],
        });
      case AiProvider.anthropic:
        request.headers.addAll({
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01',
        });
        request.body = jsonEncode({
          'model': config.model,
          'stream': true,
          'max_tokens': 4096,
          'system': system,
          'messages': messages,
        });
      case AiProvider.gemini:
        request.headers['x-goog-api-key'] = config.apiKey;
        request.body = jsonEncode({
          'systemInstruction': {
            'parts': [
              {'text': system},
            ],
          },
          'contents': messages
              .map(
                (m) => {
                  'role': m['role'] == 'assistant' ? 'model' : 'user',
                  'parts': [
                    {'text': m['content']},
                  ],
                },
              )
              .toList(),
        });
    }
    try {
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (_cancelled) return;
      var size = 0;
      final bytes = response.stream.timeout(const Duration(seconds: 90)).map((
        chunk,
      ) {
        size += chunk.length;
        if (size > 8 * 1024 * 1024) throw const FormatException('AI 响应超过大小限制');
        return chunk;
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder.bind(bytes).join();
        var detail = body.length > 500 ? body.substring(0, 500) : body;
        if (config.apiKey.isNotEmpty) {
          detail = detail.replaceAll(config.apiKey, '[redacted]');
        }
        throw StateError('HTTP ${response.statusCode}: $detail');
      }
      if (!(response.headers['content-type'] ?? '').contains(
        'text/event-stream',
      )) {
        // Some compatible endpoints return ordinary JSON even with stream=true.
        final body =
            jsonDecode(await utf8.decoder.bind(bytes).join())
                as Map<String, dynamic>;
        if (!_cancelled) yield _text(provider, body, streaming: false);
        return;
      }
      var data = <String>[];
      await for (final line
          in utf8.decoder.bind(bytes).transform(const LineSplitter())) {
        if (_cancelled) return;
        if (line.startsWith('data:')) {
          final field = line.substring(5);
          data.add(field.startsWith(' ') ? field.substring(1) : field);
        } else if (line.isEmpty && data.isNotEmpty) {
          final raw = data.join('\n');
          data = [];
          if (raw == '[DONE]') return;
          final event = jsonDecode(raw) as Map<String, dynamic>;
          if (event['error'] != null) {
            throw StateError('AI 服务错误：${event['error']}');
          }
          final text = _text(provider, event, streaming: true);
          if (text.isNotEmpty) yield text;
        }
      }
    } finally {
      _client.close();
    }
  }

  String _text(
    AiProvider provider,
    Map<String, dynamic> event, {
    required bool streaming,
  }) {
    switch (provider) {
      case AiProvider.openai:
        final choices = event['choices'] as List? ?? [];
        if (choices.isEmpty) return '';
        final body = choices.first[streaming ? 'delta' : 'message'] as Map?;
        return body?['content'] as String? ?? '';
      case AiProvider.anthropic:
        if (streaming) {
          if (event['type'] != 'content_block_delta') return '';
          final delta = event['delta'] as Map?;
          return delta?['text'] as String? ?? '';
        }
        return (event['content'] as List? ?? [])
            .where((e) => e['type'] == 'text')
            .map((e) => e['text'])
            .join();
      case AiProvider.gemini:
        final candidates = event['candidates'] as List? ?? [];
        if (candidates.isEmpty) return '';
        return ((candidates.first['content'] as Map?)?['parts'] as List? ?? [])
            .where((e) => e['thought'] != true && e['text'] is String)
            .map((e) => e['text'])
            .join();
    }
  }
}

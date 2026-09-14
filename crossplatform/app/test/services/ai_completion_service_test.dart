import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/ai_provider_config.dart';
import 'package:yourssh/providers/ai_chat_provider.dart';
import 'package:yourssh/services/ai_completion_service.dart';
import '../helpers/secure_store.dart';

class _Client extends http.BaseClient {
  _Client(this.respond);
  final Future<http.StreamedResponse> Function(http.Request) respond;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request as http.Request);
  @override
  void close() {
    closed = true;
  }
}

class _ControlledRequest extends AiCompletionService {
  final chunks = StreamController<String>();
  final entered = Completer<void>();
  bool cancelled = false;
  @override
  Stream<String> generate({
    required AiProvider provider,
    required AiProviderConfig config,
    required String system,
    required List<Map<String, String>> messages,
  }) {
    entered.complete();
    return chunks.stream;
  }

  @override
  void cancel() {
    cancelled = true;
    super.cancel();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installSecureStoreMock();
  });
  http.StreamedResponse sse(String data) => http.StreamedResponse(
    Stream.fromIterable(utf8.encode(data).map((b) => [b])),
    200,
    headers: {'content-type': 'text/event-stream; charset=utf-8'},
  );
  const config = AiProviderConfig(
    apiKey: 'fixture-key',
    model: 'fixture-model',
  );
  const history = [
    {'role': 'user', 'content': 'fixture prompt'},
  ];

  test(
    'OpenAI SSE survives fragmented UTF-8 and dispatches text incrementally',
    () async {
      final client = _Client((r) async {
        final body = jsonDecode(r.body);
        expect(body['stream'], true);
        expect(body['messages'].first['role'], 'system');
        expect(r.headers['Authorization'], 'Bearer fixture-key');
        return sse(
          'data: {"choices":[{"delta":{"content":"中"}}]}\r\n\r\n'
          'data: {"choices":[{"delta":{"content":"文"}}]}\n\ndata: [DONE]\n\n',
        );
      });
      final chunks = await AiCompletionService(client: client)
          .generate(
            provider: AiProvider.openai,
            config: config,
            system: 'system fixture',
            messages: history,
          )
          .toList();
      expect(chunks, ['中', '文']);
      expect(client.closed, true);
    },
  );

  test(
    'Anthropic system instructions are top-level and text deltas are parsed',
    () async {
      final client = _Client((r) async {
        final body = jsonDecode(r.body);
        expect(body['system'], 'system fixture');
        expect(body['messages'], history);
        return sse(
          'event: content_block_delta\ndata: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}\n\n',
        );
      });
      expect(
        await AiCompletionService(client: client)
            .generate(
              provider: AiProvider.anthropic,
              config: config,
              system: 'system fixture',
              messages: history,
            )
            .join(),
        'hello',
      );
    },
  );

  test(
    'Gemini credentials are headers and internal thoughts are not rendered',
    () async {
      final client = _Client((r) async {
        expect(r.url.toString(), isNot(contains('fixture-key')));
        expect(r.headers['x-goog-api-key'], 'fixture-key');
        return sse(
          'data: {"candidates":[{"content":{"parts":[{"thought":true,"text":"hidden"},{"text":"answer"}]}}]}\n\n',
        );
      });
      expect(
        await AiCompletionService(client: client)
            .generate(
              provider: AiProvider.gemini,
              config: config,
              system: 'system fixture',
              messages: history,
            )
            .join(),
        'answer',
      );
    },
  );

  test(
    'compatible JSON fallback returns full content and closes the client',
    () async {
      final client = _Client(
        (r) async => http.StreamedResponse(
          Stream.value(
            utf8.encode('{"choices":[{"message":{"content":"answer"}}]}'),
          ),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect(
        await AiCompletionService(client: client)
            .generate(
              provider: AiProvider.openai,
              config: config,
              system: 'system fixture',
              messages: history,
            )
            .join(),
        'answer',
      );
      expect(client.closed, true);
    },
  );

  test(
    'clearing an in-flight conversation discards late response chunks',
    () async {
      final request = _ControlledRequest();
      final provider = AiChatProvider(requestFactory: () => request);
      await provider.ready;
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'fixture');
      await provider.setActiveProvider(AiProvider.openai);
      final response = provider.send('hello');
      await request.entered.future;
      request.chunks.add('first');
      await Future<void>.delayed(Duration.zero);
      expect(provider.messages.last.content, 'first');
      provider.clear();
      expect(request.cancelled, true);
      expect(provider.loading, false);
      request.chunks.add('late');
      await request.chunks.close();
      await response;
      expect(provider.messages, isEmpty);
      provider.dispose();
    },
  );
}

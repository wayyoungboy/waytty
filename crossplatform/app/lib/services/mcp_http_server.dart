import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef McpToolCall = Future<Object?> Function(String name, Map<String, dynamic> arguments);

/// Stateless Streamable HTTP (2025-03-26), deliberately loopback-only.
class McpHttpServer {
  McpHttpServer({required this.token, required this.tools, required this.callTool});
  final String token;
  final List<Map<String, dynamic>> Function() tools;
  final McpToolCall callTool;
  HttpServer? _server;
  int _active = 0;
  int? get port => _server?.port;

  Future<void> start({int port = 0}) async {
    if (_server != null) throw StateError('MCP 已启动');
    if (token.length < 32) throw ArgumentError('MCP token is too short');
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path != '/mcp') { response.statusCode = 404; return; }
      final origin = request.headers.value('origin');
      final host = request.headers.value('host');
      if (host != '127.0.0.1:$port' && host != 'localhost:$port') {
        response.statusCode = 403; return;
      }
      if (origin != null && origin != 'http://127.0.0.1:$port' && origin != 'http://localhost:$port') {
        response.statusCode = 403; return;
      }
      if (!_equal(request.headers.value('authorization') ?? '', 'Bearer $token')) {
        response.statusCode = 401; return;
      }
      if (request.method != 'POST') { response.statusCode = 405; return; }
      if (request.headers.contentType?.mimeType != 'application/json') { response.statusCode = 415; return; }
      if (_active >= 8) { response.statusCode = 429; return; }
      _active++;
      try {
        final bytes = <int>[];
        await for (final chunk in request.timeout(const Duration(seconds: 10))) {
          if (bytes.length + chunk.length > 1024 * 1024) { response.statusCode = 413; return; }
          bytes.addAll(chunk);
        }
        final body = jsonDecode(utf8.decode(bytes));
        final batch = body is List;
        final messages = batch ? body : [body];
        if (messages.isEmpty || messages.length > 32) { response.statusCode = 400; return; }
        final replies = <Map<String, dynamic>>[];
        for (final message in messages) {
          final reply = await _dispatch(message);
          if (reply != null) replies.add(reply);
        }
        if (replies.isEmpty) { response.statusCode = 202; return; }
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(batch ? replies : replies.single));
      } finally { _active--; }
    } on FormatException {
      response.statusCode = 400;
    } on TimeoutException {
      response.statusCode = 408;
    } catch (_) {
      response.statusCode = 500;
    } finally { await response.close(); }
  }

  Future<Map<String, dynamic>?> _dispatch(Object? message) async {
    if (message is! Map || message['jsonrpc'] != '2.0' || message['method'] is! String) {
      return _error(null, -32600, 'Invalid request');
    }
    final id = message['id'];
    if (!message.containsKey('id')) return null;
    if (id is! String && id is! num) return _error(null, -32600, 'Invalid id');
    final params = message['params'] ?? <String, dynamic>{};
    if (params is! Map) return _error(id, -32602, 'Invalid params');
    Object? result;
    switch (message['method']) {
      case 'initialize':
        result = {'protocolVersion': '2025-03-26', 'capabilities': {'tools': {}},
          'serverInfo': {'name': 'waytty', 'version': '0.1.0'}};
      case 'ping': result = <String, dynamic>{};
      case 'tools/list': result = {'tools': tools()};
      case 'tools/call':
        final name = params['name'];
        final arguments = params['arguments'] ?? <String, dynamic>{};
        if (name is! String || arguments is! Map || !tools().any((t) => t['name'] == name)) {
          return _error(id, -32602, 'Unknown tool or invalid arguments');
        }
        try {
          final value = await callTool(name, Map<String, dynamic>.from(arguments));
          result = {'content': [{'type': 'text', 'text': jsonEncode(value)}]};
        } catch (e) {
          result = {'isError': true, 'content': [{'type': 'text', 'text': '$e'}]};
        }
      default: return _error(id, -32601, 'Method not found');
    }
    return {'jsonrpc': '2.0', 'id': id, 'result': result};
  }

  static Map<String, dynamic> _error(Object? id, int code, String text) =>
    {'jsonrpc': '2.0', 'id': id, 'error': {'code': code, 'message': text}};
  static bool _equal(String a, String b) {
    var difference = a.length ^ b.length;
    for (var i = 0; i < b.length; i++) {
      difference |= (i < a.length ? a.codeUnitAt(i) : 0) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}

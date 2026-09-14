import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/mcp_http_server.dart';
import 'package:yourssh/providers/local_mcp_provider.dart';

void main() {
  late McpHttpServer server;
  late HttpClient client;
  var calls = 0;
  const token = 'test-token-with-at-least-thirty-two-characters';
  setUp(() async {
    calls = 0;
    client = HttpClient();
    server = McpHttpServer(token: token,
      tools: () => [{'name': 'echo', 'inputSchema': {'type': 'object'}}],
      callTool: (name, args) async { calls++; return args; });
    await server.start();
  });
  tearDown(() async { client.close(force: true); await server.stop(); });

  Future<({int status, String body})> post(Object body, {bool auth = true, String? origin}) async {
    final request = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/mcp'));
    request.headers.contentType = ContentType.json;
    request.headers.set('Accept', 'application/json, text/event-stream');
    if (auth) request.headers.set('Authorization', 'Bearer $token');
    if (origin != null) request.headers.set('Origin', origin);
    request.write(jsonEncode(body));
    final response = await request.close();
    return (status: response.statusCode, body: await utf8.decoder.bind(response).join());
  }

  test('initialize, notification, tools/list and tools/call use real HTTP', () async {
    final init = await post({'jsonrpc':'2.0', 'id':1, 'method':'initialize', 'params': {'protocolVersion':'2025-03-26'}});
    expect(init.status, 200);
    expect(jsonDecode(init.body)['result']['serverInfo']['name'], 'waytty');
    final notification = await post({'jsonrpc':'2.0', 'method':'notifications/initialized'});
    expect(notification.status, 202);
    expect(notification.body, '');
    final list = await post({'jsonrpc':'2.0', 'id':2, 'method':'tools/list'});
    expect(jsonDecode(list.body)['result']['tools'][0]['name'], 'echo');
    final call = await post({'jsonrpc':'2.0', 'id':3, 'method':'tools/call', 'params': {'name':'echo', 'arguments': {'text':'中文'}}});
    expect(jsonDecode(jsonDecode(call.body)['result']['content'][0]['text'])['text'], '中文');
    expect(calls, 1);
  });
  test('missing token and hostile Origin cannot invoke a tool', () async {
    final message = {'jsonrpc':'2.0', 'id':1, 'method':'tools/call', 'params': {'name':'echo'}};
    expect((await post(message, auth: false)).status, 401);
    expect((await post(message, origin: 'https://attacker.example')).status, 403);
    expect((await post(message, origin: 'null')).status, 403);
    expect(calls, 0);
  });
  test('unknown tool and malformed params do not call backend', () async {
    final bad = await post({'jsonrpc':'2.0', 'id':1, 'method':'tools/call', 'params': {'name':'delete_everything'}});
    expect(jsonDecode(bad.body)['error']['code'], -32602);
    final malformed = await post({'jsonrpc':'2.0', 'id':2, 'method':'tools/call', 'params': []});
    expect(jsonDecode(malformed.body)['error']['code'], -32602);
    expect(calls, 0);
  });
  test('authorized roots reject traversal and sibling-prefix tricks', () {
    expect(LocalMcpProvider.withinRoot('/srv/app', '/srv/app/readme.md'), true);
    expect(LocalMcpProvider.withinRoot('/srv/app', '/srv/application/secret'), false);
    expect(LocalMcpProvider.withinRoot('/srv/app', '/srv/app/../secret'), false);
    expect(LocalMcpProvider.withinRoot('relative', 'relative/file'), false);
  });
}

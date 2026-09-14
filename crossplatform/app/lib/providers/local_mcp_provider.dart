import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/host.dart';
import '../models/ssh_session.dart';
import '../services/mcp_http_server.dart';
import '../services/ssh_service.dart';
import 'host_provider.dart';
import 'session_provider.dart';

class McpHostGrant {
  bool execute = false, files = false, write = false;
  String root = '';
}

/// Grants expire when the app closes. Only already-connected SSH hosts qualify.
class LocalMcpProvider extends ChangeNotifier {
  LocalMcpProvider(this.hosts, this.sessions, this.ssh);
  final HostProvider hosts;
  final SessionProvider sessions;
  final SshService ssh;
  final Map<String, McpHostGrant> grants = {};
  McpHttpServer? _server;
  bool _starting = false, _disposed = false;
  int _generation = 0;
  String? _token;
  String? get token => _token;
  int? get port => _server?.port;
  bool get running => port != null;
  String? error;

  void changeGrant(String id, void Function(McpHostGrant) change) {
    change(grants.putIfAbsent(id, McpHostGrant.new));
    notifyListeners();
  }

  Future<void> start() async {
    if (_server != null || _starting || _disposed) return;
    _starting = true;
    final generation = ++_generation;
    final random = Random.secure();
    final token = base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final server = McpHttpServer(token: token, tools: _tools, callTool: _call);
    try {
      await server.start();
      if (_disposed || generation != _generation) {
        await server.stop();
        return;
      }
      _server = server;
      _token = token;
      error = null;
    } catch (e) {
      if (generation == _generation) {
        _token = null;
        error = '$e';
      }
    } finally {
      _starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop() async {
    _generation++;
    final server = _server;
    _server = null;
    _token = null;
    await server?.stop();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _token = null;
    unawaited(_server?.stop());
    _server = null;
    super.dispose();
  }

  static Map<String, dynamic> _tool(
    String name,
    String description,
    List<String> required,
    Map<String, dynamic> properties,
  ) => {
    'name': name,
    'description': description,
    'inputSchema': {
      'type': 'object',
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    },
  };
  static const _string = {'type': 'string'};
  List<Map<String, dynamic>> _tools() => [
    _tool(
      'hosts_list',
      'List explicitly granted SSH hosts and their connection state.',
      [],
      {},
    ),
    _tool(
      'ssh_exec',
      'Execute a command on an already connected and explicitly authorized SSH host.',
      ['hostId', 'command'],
      {'hostId': _string, 'command': _string},
    ),
    _tool(
      'sftp_list',
      'List files within the authorized remote directory.',
      ['hostId', 'path'],
      {'hostId': _string, 'path': _string},
    ),
    _tool(
      'sftp_read',
      'Read a UTF-8 file (up to 1 MiB) within the authorized remote directory.',
      ['hostId', 'path'],
      {'hostId': _string, 'path': _string},
    ),
    _tool(
      'sftp_write',
      'Replace the contents of an existing UTF-8 file within an explicitly writable remote directory.',
      ['hostId', 'path', 'content'],
      {'hostId': _string, 'path': _string, 'content': _string},
    ),
  ];

  bool _connected(String id) => sessions.sshSessions.any(
    (s) => s.host.id == id && s.status == SessionStatus.connected && !s.isWatch,
  );
  Future<Object?> _call(String name, Map<String, dynamic> args) async {
    if (name == 'hosts_list') {
      return hosts.allHosts
          .where((h) => grants.containsKey(h.id))
          .map(
            (h) => {
              'id': h.id,
              'label': h.label,
              'address': h.host,
              'connected': _connected(h.id),
              'execute': grants[h.id]!.execute,
              'files': grants[h.id]!.files,
              'write': grants[h.id]!.write,
            },
          )
          .toList();
    }
    final id = args['hostId'];
    if (id is! String) throw ArgumentError('hostId is required');
    final Host? host = hosts.byId(id);
    final grant = grants[id];
    if (host == null ||
        grant == null ||
        host.protocol != HostProtocol.ssh ||
        !_connected(id)) {
      throw StateError('Host is not authorized or connected');
    }
    if (name == 'ssh_exec') {
      if (!grant.execute) throw StateError('Command execution is not allowed');
      final command = args['command'];
      if (command is! String || command.isEmpty || command.length > 65536) {
        throw ArgumentError('Invalid command');
      }
      final result = await ssh.execForMcp(host, command);
      return {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'exitCode': result.exitCode,
      };
    }
    if (!grant.files || grant.root.trim().isEmpty) {
      throw StateError('File access is not allowed');
    }
    final path = args['path'];
    if (path is! String || path.contains('\x00') || !p.posix.isAbsolute(path)) {
      throw ArgumentError('An absolute path is required');
    }
    final client = await ssh.openSftp(host, interactive: false);
    try {
      final grantedRoot = grant.root;
      final root = p.posix.normalize(await client.absolute(grantedRoot));
      final canonical = p.posix.normalize(await client.absolute(path));
      if (!withinRoot(root, canonical)) {
        throw StateError('Path is outside the authorized directory');
      }
      // Recheck after awaits so revoking a grant affects subsequent operations.
      if (!grant.files || grant.root != grantedRoot || !running) {
        throw StateError('File access was revoked');
      }
      if (name == 'sftp_list') {
        return (await client.listdir(canonical))
            .where((e) => e.filename != '.' && e.filename != '..')
            .map(
              (e) => {
                'name': e.filename,
                'directory': e.attr.isDirectory,
                'size': e.attr.size,
                'permissions': e.attr.mode?.value,
              },
            )
            .toList();
      }
      if (name == 'sftp_write') {
        if (!grant.write) throw StateError('Writing is not allowed');
        final content = args['content'];
        if (content is! String || utf8.encode(content).length > 1024 * 1024) {
          throw ArgumentError('File exceeds 1 MiB');
        }
        final file = await client.open(
          canonical,
          mode: SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );
        try {
          await file.writeBytes(Uint8List.fromList(utf8.encode(content)));
        } finally {
          await file.close();
        }
        return {'written': true};
      }
      final file = await client.open(canonical);
      try {
        final bytes = await file.readBytes(length: 1024 * 1024 + 1);
        if (bytes.length > 1024 * 1024) throw StateError('File exceeds 1 MiB');
        return {'content': utf8.decode(bytes)};
      } finally {
        await file.close();
      }
    } finally {
      client.close();
    }
  }

  @visibleForTesting
  static bool withinRoot(String root, String path) =>
      p.posix.isAbsolute(root) &&
      (p.posix.equals(root, path) || p.posix.isWithin(root, path));
}

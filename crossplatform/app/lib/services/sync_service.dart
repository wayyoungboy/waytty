import 'dart:convert';
import '../models/host.dart';

class SyncPayload {
  final List<Host> hosts;
  final Map<String, String> passwords;
  final DateTime updatedAt;
  final Map<String, dynamic> workspace;
  SyncPayload({
    required this.hosts,
    required this.passwords,
    required this.updatedAt,
    this.workspace = const {},
  });
}

/// Shared payload codec for manual cloud backup and local device transfer.
abstract final class SyncService {
  static String buildPayload({
    required List<Host> hosts,
    required Map<String, String> passwords,
    Map<String, dynamic> workspace = const {},
  }) {
    return jsonEncode({
      'hosts': hosts.map((h) {
        final json = h.toJson();
        json.remove('detectedOs');
        return json;
      }).toList(),
      'passwords': passwords,
      'workspace': workspace,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static SyncPayload parsePayload(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final hosts = (map['hosts'] as List)
        .map((e) => Host.fromJson(e as Map<String, dynamic>))
        .toList();
    final passwords = (map['passwords'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as String),
    );
    return SyncPayload(
      hosts: hosts,
      passwords: passwords,
      workspace: Map<String, dynamic>.from(map['workspace'] as Map? ?? {}),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

}

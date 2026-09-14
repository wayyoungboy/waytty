import 'package:uuid/uuid.dart';

class WorkspaceNote {
  WorkspaceNote({
    String? id,
    this.title = '未命名笔记',
    this.body = '',
    this.hostId,
    this.group,
    DateTime? modifiedAt,
  }) : id = id ?? const Uuid().v4(),
       modifiedAt = modifiedAt ?? DateTime.now();
  final String id;
  String title, body;
  String? hostId, group;
  DateTime modifiedAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'hostId': hostId,
    'group': group,
    'modifiedAt': modifiedAt.toIso8601String(),
  };
  factory WorkspaceNote.fromJson(Map<String, dynamic> json) => WorkspaceNote(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    hostId: json['hostId'] as String?,
    group: json['group'] as String?,
    modifiedAt: DateTime.parse(json['modifiedAt'] as String),
  );
}

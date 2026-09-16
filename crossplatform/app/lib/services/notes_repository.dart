import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/workspace_note.dart';

class NotesRepository {
  static const storageKey = 'waytty.notes.v1';
  Future<void> _pending = Future.value();

  Future<List<WorkspaceNote>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => WorkspaceNote.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Snapshot before enqueueing; later keystrokes must not mutate this save.
  Future<void> save(List<WorkspaceNote> notes) {
    final encoded = jsonEncode(notes.map((n) => n.toJson()).toList());
    final result = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, encoded)) {
        throw StateError('笔记保存失败');
      }
      if ((prefs.getString('supabase_url') ?? '').isNotEmpty) {
        await prefs.setString('sync_local_revision', const Uuid().v4());
        await prefs.setBool('sync_pending_push', true);
      }
    });
    _pending = result.catchError((Object _) {});
    return result;
  }
}

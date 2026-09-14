import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workspace_note.dart';
import 'notes_repository.dart';

/// Portable workspace data. Machine paths, API credentials and MCP grants
/// never enter this map. It is encrypted together with the host payload.
class WorkspaceSync {
  static const _groups = 'yourssh.pinned_groups';
  static const _snippets = 'yourssh.snippets';
  static Future<Map<String, dynamic>> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'notes': prefs.getString(NotesRepository.storageKey) ?? '[]',
      'groups': prefs.getStringList(_groups) ?? <String>[],
      'snippets': prefs.getString(_snippets) ?? '[]',
    };
  }

  static Future<void> restore(Map<String, dynamic> data) async {
    if (data.isEmpty) return; // older peer: preserve this device's extra data
    final notes = data['notes'];
    final groups = data['groups'];
    final snippets = data['snippets'];
    if (notes is! String || snippets is! String || groups is! List || groups.any((e) => e is! String)) {
      throw const FormatException('Invalid workspace snapshot');
    }
    for (final note in jsonDecode(notes) as List) {
      WorkspaceNote.fromJson(Map<String, dynamic>.from(note as Map));
    }
    final snippetList = jsonDecode(snippets);
    if (snippetList is! List || snippetList.any((e) => e is! Map || e['command'] is! String || e['label'] is! String)) {
      throw const FormatException('Invalid snippet snapshot');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NotesRepository.storageKey, notes);
    await prefs.setStringList(_groups, groups.cast<String>());
    await prefs.setString(_snippets, snippets);
  }
}

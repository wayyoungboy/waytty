import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/workspace_note.dart';
import 'package:yourssh/services/notes_repository.dart';
import 'package:yourssh/services/workspace_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('portable workspace round trip excludes machine credentials and paths', () async {
    SharedPreferences.setMockInitialValues({
      NotesRepository.storageKey: jsonEncode([WorkspaceNote(title: '中文', body: '笔记', hostId: 'host').toJson()]),
      'yourssh.snippets': '[{"label":"查看文件","command":"ls -al"}]',
      'yourssh.pinned_groups': ['生产/数据库'],
      'recordingPath': '/private/machine/path',
      'ai_config_openai_key': 'not-a-real-key',
    });
    final snapshot = await WorkspaceSync.snapshot();
    expect(snapshot.keys, unorderedEquals(['notes', 'groups', 'snippets']));
    SharedPreferences.setMockInitialValues({});
    await WorkspaceSync.restore(snapshot);
    expect((await NotesRepository().load()).single.title, '中文');
    expect((await SharedPreferences.getInstance()).getStringList('yourssh.pinned_groups'), ['生产/数据库']);
  });
  test('invalid snapshot is rejected before writing any keys', () async {
    SharedPreferences.setMockInitialValues({NotesRepository.storageKey: '[]'});
    await expectLater(WorkspaceSync.restore({'notes':'[]', 'groups':[], 'snippets':'{}'}), throwsFormatException);
    expect((await SharedPreferences.getInstance()).getString(NotesRepository.storageKey), '[]');
  });
}

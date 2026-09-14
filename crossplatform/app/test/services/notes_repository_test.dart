import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/workspace_note.dart';
import 'package:yourssh/services/notes_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('queued edits keep the newest snapshot including associations', () async {
    final repository = NotesRepository();
    final note = WorkspaceNote(title: '运维手册', body: 'first', hostId: 'server', group: '生产/数据库');
    final first = repository.save([note]);
    note.body = '# 最终版本\n```sh\nls -la\n```';
    final second = repository.save([note]);
    await Future.wait([first, second]);
    final restored = (await NotesRepository().load()).single;
    expect(restored.body, note.body);
    expect(restored.id, note.id);
    expect(restored.hostId, 'server');
    expect(restored.group, '生产/数据库');
  });
  test('malformed storage reports an error and preserves original content', () async {
    SharedPreferences.setMockInitialValues({NotesRepository.storageKey: '{broken'});
    await expectLater(NotesRepository().load(), throwsFormatException);
    expect((await SharedPreferences.getInstance()).getString(NotesRepository.storageKey), '{broken');
  });
}

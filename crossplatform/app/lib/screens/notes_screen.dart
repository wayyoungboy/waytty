import 'package:waytty_l10n/waytty_l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/workspace_note.dart';
import '../providers/host_provider.dart';
import '../services/notes_repository.dart';
import '../theme/app_theme.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _repository = NotesRepository();
  final _title = TextEditingController(), _body = TextEditingController();
  List<WorkspaceNote> _notes = [];
  WorkspaceNote? _active;
  String _query = '';
  String? _error;
  bool _loaded = false, _preview = true, _saving = false;
  int _saveRevision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final notes = await _repository.load();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loaded = true;
      });
      if (notes.isNotEmpty) _select(notes.first);
    } catch (e) {
      if (mounted) setState(() => _error = '无法读取笔记：$e');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _select(WorkspaceNote note) {
    setState(() {
      _active = note;
      _title.text = note.title;
      _body.text = note.body;
    });
  }

  Future<void> _save() async {
    final revision = ++_saveRevision;
    setState(() => _saving = true);
    try {
      await _repository.save(_notes);
      if (mounted && revision == _saveRevision) {
        setState(() {
          _saving = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  void _change() {
    final note = _active;
    if (note == null) return;
    note.title = _title.text;
    note.body = _body.text;
    note.modifiedAt = DateTime.now();
    unawaited(_save());
  }

  Future<void> _add({String? title, String? body}) async {
    final note = WorkspaceNote(title: title ?? '未命名笔记', body: body ?? '');
    _notes.insert(0, note);
    _select(note);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final hosts = context.watch<HostProvider>().allHosts;
    final note = _active;
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          SizedBox(
            width: box.maxWidth < 850 ? 210 : 250,
            child: ColoredBox(
              color: AppColors.sidebar,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const LText("笔记"),
                        const Spacer(),
                        IconButton(
                          onPressed: _loaded ? _import : null,
                          tooltip: tr(context, "导入 Markdown"),
                          icon: const Icon(Icons.file_open_outlined, size: 17),
                        ),
                        IconButton(
                          onPressed: _loaded ? () => _add() : null,
                          tooltip: tr(context, "新建笔记"),
                          icon: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      onChanged: (text) =>
                          setState(() => _query = text.toLowerCase()),
                      decoration:  InputDecoration(
                        hintText: tr(context, "搜索笔记"),
                        prefixIcon: Icon(Icons.search, size: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final n in _notes.where(
                          (n) => '${n.title}\n${n.body}'.toLowerCase().contains(
                            _query,
                          ),
                        ))
                          ListTile(
                            selected: n.id == note?.id,
                            selectedColor: AppColors.accent,
                            selectedTileColor: const Color(0xFF26342D),
                            dense: true,
                            title: LText(
                              n.title.isEmpty ? "未命名笔记" : LRaw(n.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              n.body.replaceAll('\n', ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            onTap: () => _select(n),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!),
                    actions: [
                      TextButton(
                        onPressed: _loaded ? _save : _load,
                        child: const LText("重试"),
                      ),
                    ],
                  ),
                if (note == null)
                  const Expanded(child: Center(child: LText("创建笔记，记录命令和运维文档")))
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _title,
                            onChanged: (_) => _change(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration:  InputDecoration(
                              border: InputBorder.none,
                              hintText: tr(context, "笔记标题"),
                            ),
                          ),
                        ),
                        LText(
                          _saving ? "保存中…" : "已保存",
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _preview = !_preview),
                          tooltip: tr(context, "切换预览"),
                          icon: Icon(
                            _preview ? Icons.preview : Icons.edit_note,
                          ),
                        ),
                        IconButton(
                          onPressed: _export,
                          tooltip: tr(context, "导出 Markdown"),
                          icon: const Icon(Icons.ios_share, size: 18),
                        ),
                        IconButton(
                          onPressed: _delete,
                          tooltip: tr(context, "删除笔记"),
                          icon: const Icon(Icons.delete_outline, size: 18),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        PopupMenuButton<String>(
                          tooltip: tr(context, "关联连接"),
                          onSelected: (id) {
                            note.hostId = id.isEmpty ? null : id;
                            _save();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: '',
                              child: LText("不关联连接"),
                            ),
                            for (final h in hosts)
                              PopupMenuItem(value: h.id, child: Text(h.label)),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.link, size: 15),
                                const SizedBox(width: 6),
                                Text(
                                  hosts
                                          .where((h) => h.id == note.hostId)
                                          .firstOrNull
                                          ?.label ??
                                      tr(context, '关联连接'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        PopupMenuButton<String>(
                          tooltip: tr(context, "关联分组"),
                          onSelected: (g) {
                            note.group = g.isEmpty ? null : g;
                            _save();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: '',
                              child: LText("不关联分组"),
                            ),
                            for (final g in {
                              ...context.read<HostProvider>().pinnedGroups,
                              ...hosts.map((h) => h.group),
                            }.where((g) => g.isNotEmpty))
                              PopupMenuItem(value: g, child: Text(g)),
                          ],
                          child: Text(
                            note.group ?? tr(context, '关联分组'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _body,
                            onChanged: (_) => _change(),
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.6,
                            ),
                            decoration:  InputDecoration(
                              hintText: tr(context, "支持 Markdown，输入后自动保存"),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(20),
                            ),
                          ),
                        ),
                        if (_preview && box.maxWidth >= 950) ...[
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: Markdown(
                              data: note.body,
                              selectable: true,
                              sizedImageBuilder: (config) =>
                                  Text(config.alt ?? tr(context, '[Image]')),
                              onTapLink: (text, href, title) {
                                final uri = Uri.tryParse(href ?? '');
                                if (uri != null &&
                                    {'http', 'https'}.contains(uri.scheme)) {
                                  launchUrl(uri);
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final note = _active;
    if (note == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText("删除笔记"),
        content: LText(LMessage("删除“{0}”？", [note.title])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LText("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LText("删除"),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _notes.remove(note);
      _active = null;
    });
    if (_notes.isNotEmpty) _select(_notes.first);
    await _save();
  }

  Future<void> _import() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Markdown',
            extensions: ['md', 'txt', 'markdown'],
          ),
        ],
      );
      if (file == null) return;
      final body = await file.readAsString();
      if (mounted) {
        await _add(
          title: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          body: body,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '导入失败：$e');
    }
  }

  Future<void> _export() async {
    final note = _active;
    if (note == null) return;
    try {
      final title = note.title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final path = await getSaveLocation(suggestedName: '$title.md');
      if (path != null) {
        await XFile.fromData(
          utf8.encode(note.body),
          mimeType: 'text/markdown',
        ).saveTo(path.path);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '导出失败：$e');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:waytty_l10n/waytty_l10n.dart';

/// Per-session expansion state. Only explicitly expanded directories are read.
class FileTreeCache<T> {
  String? root;
  int? revision;
  final children = <String, List<T>>{};
  final expanded = <String>{};
}

class FileTreeView<T> extends StatefulWidget {
  final String root;
  final int revision;
  final List<T> entries;
  final FileTreeCache<T> cache;
  final String Function(T) pathOf;
  final String Function(T) nameOf;
  final bool Function(T) isDirectory;
  final Future<List<T>> Function(String) listDirectory;
  final void Function(T) onOpen;
  final void Function(T) onSelect;
  final bool Function(T) isSelected;
  final Widget Function(T, Widget) wrapEntry;
  final String filter;

  const FileTreeView({
    super.key,
    required this.root,
    required this.revision,
    required this.entries,
    required this.cache,
    required this.pathOf,
    required this.nameOf,
    required this.isDirectory,
    required this.listDirectory,
    required this.onOpen,
    required this.onSelect,
    required this.isSelected,
    required this.wrapEntry,
    this.filter = '',
  });

  @override
  State<FileTreeView<T>> createState() => _FileTreeViewState<T>();
}

class _FileTreeViewState<T> extends State<FileTreeView<T>> {
  final _loading = <String>{};
  final _errors = <String, Object>{};
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _syncRoot();
  }

  @override
  void didUpdateWidget(covariant FileTreeView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRoot();
  }

  @override
  void dispose() {
    // An interrupted expansion must be retryable when this session reopens.
    widget.cache.expanded.removeAll(_loading);
    widget.cache.expanded.removeAll(_errors.keys);
    super.dispose();
  }

  void _syncRoot() {
    final cache = widget.cache;
    if (cache.root == widget.root && cache.revision == widget.revision) return;
    _generation++;
    _loading.clear();
    _errors.clear();
    cache.children.clear();
    cache.expanded.clear();
    cache.root = widget.root;
    cache.revision = widget.revision;
  }

  Future<void> _toggle(T entry) async {
    final path = widget.pathOf(entry);
    final cache = widget.cache;
    if (cache.expanded.contains(path)) {
      setState(() => cache.expanded.remove(path));
      return;
    }
    setState(() => cache.expanded.add(path));
    if (cache.children.containsKey(path) || _loading.contains(path)) return;
    await _load(path);
  }

  Future<void> _load(String path) async {
    final generation = _generation;
    setState(() {
      _loading.add(path);
      _errors.remove(path);
    });
    try {
      final entries = await widget.listDirectory(path);
      if (!mounted || generation != _generation) return;
      entries.sort((a, b) {
        final type = (widget.isDirectory(a) ? 0 : 1).compareTo(
          widget.isDirectory(b) ? 0 : 1,
        );
        return type != 0
            ? type
            : widget
                  .nameOf(a)
                  .toLowerCase()
                  .compareTo(widget.nameOf(b).toLowerCase());
      });
      setState(() => widget.cache.children[path] = entries);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _errors[path] = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading.remove(path));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final query = widget.filter.toLowerCase();
    void append(List<T> entries, int depth) {
      for (final entry in entries) {
        final directory = widget.isDirectory(entry);
        // Keep directories available for navigation; do not recursively scan
        // the server to filter names. Only loaded files are filtered.
        if (!directory && !widget.nameOf(entry).toLowerCase().contains(query)) {
          continue;
        }
        final path = widget.pathOf(entry);
        final expanded = widget.cache.expanded.contains(path);
        rows.add(
          widget.wrapEntry(
            entry,
            InkWell(
              key: ValueKey('file-tree:$path'),
              onTap: () {
                widget.onSelect(entry);
                if (directory) _toggle(entry);
              },
              child: Container(
                height: 30,
                color: widget.isSelected(entry)
                    ? const Color(0xFF22C55E).withValues(alpha: 0.18)
                    : null,
                padding: EdgeInsets.only(left: (depth * 16.0).clamp(0, 128)),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: directory
                          ? IconButton(
                              tooltip: tr(
                                context,
                                expanded ? 'Collapse folder' : 'Expand folder',
                              ),
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              constraints: const BoxConstraints.tightFor(
                                width: 26,
                                height: 26,
                              ),
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _toggle(entry),
                              icon: Icon(
                                expanded
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                              ),
                            )
                          : null,
                    ),
                    Icon(
                      directory
                          ? (expanded ? Icons.folder_open : Icons.folder)
                          : Icons.insert_drive_file_outlined,
                      size: 16,
                      color: directory
                          ? const Color(0xFFE5C45A)
                          : const Color(0xFF999999),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: GestureDetector(
                        onDoubleTap: () => widget.onOpen(entry),
                        child: Tooltip(
                          message: path,
                          child: Text(
                            widget.nameOf(entry),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFD4D4D4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        );
        if (!directory || !expanded) continue;
        if (_loading.contains(path)) {
          rows.add(
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          );
        } else if (_errors.containsKey(path)) {
          rows.add(
            ListTile(
              dense: true,
              title: Text(
                '${_errors[path]}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
              trailing: IconButton(
                tooltip: tr(context, 'Retry'),
                onPressed: () => _load(path),
                icon: const Icon(Icons.refresh, size: 16),
              ),
            ),
          );
        } else if (widget.cache.children[path]?.isEmpty ?? false) {
          rows.add(
            Padding(
              padding: EdgeInsets.only(left: 26 + (depth + 1) * 16.0),
              child: const LText(
                'Empty directory',
                style: TextStyle(fontSize: 11, color: Color(0xFF777777)),
              ),
            ),
          );
        } else {
          append(widget.cache.children[path] ?? [], depth + 1);
        }
      }
    }

    append(widget.entries, 0);
    return ListView.builder(
      key: PageStorageKey('file-tree-scroll:${widget.root}'),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }
}

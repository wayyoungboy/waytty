import 'package:waytty_l10n/waytty_l10n.dart';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import 'port_forwarding_screen.dart';
import '../theme/app_theme.dart';
import '../models/serial_models.dart';
import '../services/serial/serial_backend.dart';
import 'serial/serial_connection_panel.dart';

/// Shared desktop/tablet connection browser. No desktop-only protocol code.
class ConnectionCenter extends StatefulWidget {
  const ConnectionCenter({
    super.key,
    required this.onAdd,
    required this.onEdit,
    required this.onConnect,
    required this.onImport,
    required this.onNewGroup,
    this.onSerialConnect,
  });
  final void Function(HostProtocol protocol, String? group) onAdd;
  final ValueChanged<Host> onEdit;
  final Future<void> Function(Host) onConnect;
  final VoidCallback onImport, onNewGroup;
  final Future<void> Function(SerialDeviceInfo, SerialConfig, SerialBackend)? onSerialConnect;
  @override
  State<ConnectionCenter> createState() => _ConnectionCenterState();
}

class _ConnectionCenterState extends State<ConnectionCenter> {
  HostProtocol? _protocol = HostProtocol.ssh;
  String _filter = '全部', _query = '';
  String? _group;
  final Set<String> _selected = {};
  bool _showGroups = true;
  bool _serial = false;
  String? _error;

  List<Host> _filtered(HostProvider provider) {
    final q = _query.toLowerCase();
    final hosts = provider.allHosts
        .where(
          (h) =>
              h.protocol == _protocol &&
              (_group == null ||
                  h.group == _group ||
                  h.group.startsWith('$_group/')) &&
              (_filter != '收藏' || h.favorite) &&
              (_filter != '最近' || h.lastUsedAt != null) &&
              (_filter != '常用' || h.connectionCount > 0) &&
              [
                h.label,
                h.host,
                h.group,
                h.note,
                ...h.tags,
              ].any((s) => s.toLowerCase().contains(q)),
        )
        .toList();
    if (_filter == '最近') {
      hosts.sort((a, b) => b.lastUsedAt!.compareTo(a.lastUsedAt!));
    }
    if (_filter == '常用') {
      hosts.sort((a, b) => b.connectionCount.compareTo(a.connectionCount));
    }
    return hosts;
  }

  Future<void> _connect(Host host) async {
    try {
      await context.read<HostProvider>().updateHost(
        host.copyWith(
          lastUsedAt: DateTime.now(),
          connectionCount: host.connectionCount + 1,
        ),
      );
      await widget.onConnect(host);
    } catch (e) {
      if (mounted) setState(() => _error = '连接失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HostProvider>();
    final hosts = _filtered(provider);
    final groups = {
      ...provider.pinnedGroups,
      ...provider.allHosts.map((h) => h.group),
    }.where((g) => g.isNotEmpty).toList()..sort();
    // Include parents of nested groups even when they contain no direct hosts.
    final allGroups = <String>{};
    for (final group in groups) {
      final parts = group.split('/');
      for (var n = 1; n <= parts.length; n++) {
        allGroups.add(parts.take(n).join('/'));
      }
    }
    final sortedGroups = allGroups.toList()..sort();
    return Column(
      children: [
        Container(
          height: 46,
          decoration: const BoxDecoration(
            color: AppColors.sidebar,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _protocolTab('SSH', Icons.terminal, HostProtocol.ssh),
              _protocolTab(
                'Telnet',
                Icons.settings_ethernet,
                HostProtocol.telnet,
              ),
              if (widget.onSerialConnect != null)
                TextButton.icon(onPressed: () => setState(() => _serial = true),
                  icon: Icon(Icons.cable, size: 15, color: _serial ? AppColors.accent : AppColors.textSecondary),
                  label: LText('Serial', style: TextStyle(color: _serial ? AppColors.accent : AppColors.textSecondary))),
              _protocolTab('隧道', Icons.alt_route, null),
              const Spacer(),
              if (_protocol != null && !_serial)
                TextButton.icon(
                  onPressed: () => widget.onAdd(_protocol!, _group),
                  icon: const Icon(Icons.add, size: 16),
                  label: const LText("新建连接"),
                ),
            ],
          ),
        ),
        if (_serial)
          Expanded(child: SerialConnectionPanel(onConnect: widget.onSerialConnect!))
        else if (_protocol == null)
          const Expanded(child: PortForwardingScreen())
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 750;
                return Row(
                  children: [
                    if (wide && _showGroups)
                      Container(
                        width: 228,
                        decoration: const BoxDecoration(
                          color: AppColors.sidebar,
                          border: Border(
                            right: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                              child: Row(
                                children: [
                                  const Expanded(child: LText(
                                    "连接分组",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  )),
                                  IconButton(
                                    onPressed: widget.onNewGroup,
                                    tooltip: tr(context, "新建分组"),
                                    icon: const Icon(
                                      Icons.create_new_folder_outlined,
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final item in [
                              ('全部', Icons.apps),
                              ('收藏', Icons.star_border),
                              ('最近', Icons.history),
                              ('常用', Icons.bolt),
                            ])
                              _groupRow(
                                item.$1,
                                item.$2,
                                _group == null && _filter == item.$1,
                                () => setState(() {
                                  _group = null;
                                  _filter = item.$1;
                                }),
                              ),
                            const Divider(height: 28),
                            Expanded(
                              child: ListView(
                                children: [
                                  for (final g in sortedGroups)
                                    DragTarget<Host>(
                                      onAcceptWithDetails: (d) =>
                                          provider.updateHost(
                                            d.data.copyWith(group: g),
                                          ),
                                      builder: (_, candidates, rejects) =>
                                          _groupRow(
                                            g.split('/').last,
                                            Icons.folder_outlined,
                                            _group == g ||
                                                candidates.isNotEmpty,
                                            () => setState(() {
                                              _group = g;
                                              _filter = '全部';
                                            }),
                                            indent:
                                                (g.split('/').length - 1) *
                                                14.0,
                                            groupPath: g,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: LText(
                                LMessage("{0} 个连接", [provider.allHosts.where((h) => h.protocol == _protocol).length]),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: () => setState(
                                    () => _showGroups = !_showGroups,
                                  ),
                                  tooltip: tr(context, "分组侧栏"),
                                  icon: const Icon(
                                    Icons.view_sidebar_outlined,
                                    size: 17,
                                  ),
                                ),
                                if (!wide)
                                  PopupMenuButton<String>(
                                    tooltip: tr(context, "筛选分组"),
                                    onSelected: (s) => setState(() {
                                      _group = s.isEmpty ? null : s;
                                    }),
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: '',
                                        child: LText("全部分组"),
                                      ),
                                      for (final g in sortedGroups)
                                        PopupMenuItem(value: g, child: Text(g)),
                                    ],
                                  ),
                                Expanded(
                                  child: SizedBox(
                                    height: 34,
                                    child: TextField(
                                      onChanged: (s) =>
                                          setState(() => _query = s),
                                      decoration:  InputDecoration(
                                        hintText: tr(context, "搜索名称、地址、分组或备注"),
                                        filled: true,
                                        fillColor: Color(0xFF1E1E1E),
                                        border: OutlineInputBorder(
                                          borderSide: BorderSide.none,
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(6),
                                          ),
                                        ),
                                        prefixIcon: Icon(
                                          Icons.search,
                                          size: 17,
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (_selected.isNotEmpty)
                                  TextButton(
                                    onPressed: () async {
                                      for (final h in hosts.where(
                                        (h) => _selected.contains(h.id),
                                      )) {
                                        await _connect(h);
                                      }
                                    },
                                    child: LText(LMessage("连接所选 ({0})", [_selected.length])),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: tr(context, "导入与导出"),
                                  icon: const Icon(Icons.more_horiz, size: 18),
                                  onSelected: (action) {
                                    if (action == 'import') {
                                      widget.onImport();
                                    } else {
                                      _export(hosts);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'import',
                                      child: LText("导入连接"),
                                    ),
                                    PopupMenuItem(
                                      value: 'export',
                                      child: LText("导出当前列表（不含密码）"),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (_error != null || provider.loadError != null)
                            MaterialBanner(
                              content: Text(_error ?? provider.loadError!),
                              actions: [
                                TextButton(
                                  onPressed: provider.loadError != null
                                      ? null
                                      : () => setState(() => _error = null),
                                  child: const LText("关闭"),
                                ),
                              ],
                            ),
                          Container(
                            height: 34,
                            color: const Color(0xFF1B1B1B),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: const Row(
                              children: [
                                SizedBox(width: 44),
                                Expanded(
                                  flex: 3,
                                  child: LText("名称", style: _caption),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: LText("地址", style: _caption),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: LText("备注 / 标签", style: _caption),
                                ),
                                SizedBox(width: 112),
                              ],
                            ),
                          ),
                          Expanded(
                            child: hosts.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.dns_outlined,
                                          size: 40,
                                          color: Color(0xFF454545),
                                        ),
                                        const SizedBox(height: 16),
                                        LText(
                                          _query.isNotEmpty
                                              ? '没有匹配的连接'
                                              : _group != null
                                                  ? LMessage('“{0}”中还没有连接', [_group])
                                                  : _filter == '全部'
                                                      ? '还没有连接'
                                                      : LMessage('暂无{0}连接', [LMessage(_filter, const [])]),
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextButton.icon(
                                          onPressed: () =>
                                              widget.onAdd(_protocol!, _group),
                                          icon: const Icon(Icons.add, size: 16),
                                          label: const LText("添加连接"),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: hosts.length,
                                    itemBuilder: (context, index) =>
                                        _hostRow(hosts[index], provider),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  static const _caption = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 11,
  );
  Widget _protocolTab(String label, IconData icon, HostProtocol? protocol) =>
      InkWell(
        onTap: () => setState(() {
          _protocol = protocol;
          _serial = false;
          _selected.clear();
        }),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: !_serial && _protocol == protocol
                ? const Border(
                    bottom: BorderSide(color: AppColors.accent, width: 2),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: !_serial && _protocol == protocol
                    ? AppColors.accent
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              LText(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: !_serial && _protocol == protocol
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _groupRow(
    String title,
    IconData icon,
    bool selected,
    VoidCallback onTap, {
    double indent = 0,
    String? groupPath,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    child: Material(
      color: selected ? const Color(0xFF26342D) : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12 + indent, 10, 12, 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LText(
                  groupPath == null ? title : LRaw(title),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? AppColors.accent : AppColors.textPrimary,
                  ),
                ),
              ),
              if (groupPath != null)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    tooltip: tr(context, "分组操作"),
                    icon: const Icon(Icons.more_horiz, size: 15),
                    onSelected: (action) => _groupAction(groupPath, action),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: LText("重命名 / 移动分组")),
                      PopupMenuItem(
                        value: 'dissolve',
                        child: LText("移除分组，保留连接"),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _hostRow(Host host, HostProvider provider) => LongPressDraggable<Host>(
    data: host,
    feedback: Material(
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(host.label),
      ),
    ),
    child: InkWell(
      onDoubleTap: () => _connect(host),
      onTap: () => setState(() {
        if (!_selected.add(host.id)) _selected.remove(host.id);
      }),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: _selected.contains(host.id) ? const Color(0xFF19271F) : null,
          border: const Border(bottom: BorderSide(color: Color(0xFF222222))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Icon(
                host.protocol == HostProtocol.telnet
                    ? Icons.settings_ethernet
                    : Icons.computer,
                size: 23,
                color: const Color(0xFF929C97),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(host.label, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 5),
                        LText(
                          host.group.isEmpty ? "未分组" : LRaw(host.group),
                          style: _caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => provider.updateHost(
                      host.copyWith(favorite: !host.favorite),
                    ),
                    tooltip: tr(context, host.favorite ? "取消收藏" : "收藏"),
                    icon: Icon(
                      host.favorite ? Icons.star : Icons.star_border,
                      size: 14,
                      color: host.favorite
                          ? AppColors.accent
                          : const Color(0xFF555555),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: LText(
                LMessage("{0}:{1}", [host.host, host.port]),
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: LText(
                host.note.isNotEmpty ? LRaw(host.note) : LRaw(host.tags.join(' · ')),
                style: _caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 112,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _connect(host),
                    child: const LText("连接"),
                  ),
                  PopupMenuButton<String>(
                    tooltip: tr(context, "连接操作"),
                    icon: const Icon(Icons.more_vert, size: 17),
                    onSelected: (value) async {
                      if (value == 'edit') widget.onEdit(host);
                      if (value == 'duplicate') {
                        await _mutate(() async {
                          await provider.duplicateHost(host);
                        });
                        return;
                      }
                      if (value == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const LText("删除连接"),
                            content: LText(LMessage("删除“{0}”及其保存的凭据？", [host.label])),
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
                        if (confirmed == true) {
                          await _mutate(() => provider.deleteHost(host.id));
                          if (mounted) {
                            setState(() => _selected.remove(host.id));
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: LText("编辑连接")),
                      PopupMenuItem(value: 'duplicate', child: LText("复制连接")),
                      PopupMenuItem(value: 'delete', child: LText("删除连接")),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _mutate(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => _error = '操作失败：$e');
    }
  }

  Future<void> _groupAction(String group, String action) async {
    final provider = context.read<HostProvider>();
    if (action == 'rename') {
      var name = group;
      final target = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LText("重命名 / 移动分组"),
          content: TextFormField(
            initialValue: group,
            autofocus: true,
            decoration:  InputDecoration(
              labelText: tr(context, "分组路径"),
              hintText: tr(context, "例如：工作 / 生产环境"),
            ),
            onChanged: (value) => name = value,
            onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const LText("取消"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, name),
              child: const LText("保存"),
            ),
          ],
        ),
      );
      if (target == null || !mounted) return;
      await _mutate(() async {
        await provider.renameGroup(group, target);
        if (mounted) {
          setState(() {
            if (_group == group || (_group?.startsWith('$group/') ?? false)) {
              _group = '${target.trim()}${_group!.substring(group.length)}';
            }
          });
        }
      });
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LText("移除分组"),
          content: LText(LMessage("移除“{0}”及子分组，其中的连接和凭据将保留为未分组。", [group])),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LText("取消"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LText("移除分组"),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _mutate(() => provider.dissolveGroup(group));
      if (mounted) {
        setState(() {
          _group = null;
          _filter = '全部';
        });
      }
    }
  }

  Future<void> _export(List<Host> hosts) async {
    try {
      final location = await getSaveLocation(
        suggestedName: 'waytty-connections.json',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (location == null) return;
      final data = const JsonEncoder.withIndent(
        '  ',
      ).convert(hosts.map((h) => h.toJson()).toList());
      await XFile.fromData(
        utf8.encode(data),
        mimeType: 'application/json',
      ).saveTo(location.path);
    } catch (e) {
      if (mounted) setState(() => _error = '导出失败：$e');
    }
  }
}

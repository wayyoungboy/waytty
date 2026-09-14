import 'package:waytty_l10n/waytty_l10n.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../providers/local_mcp_provider.dart';
import '../theme/app_theme.dart';

class McpScreen extends StatelessWidget {
  const McpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final mcp = context.watch<LocalMcpProvider>();
    final hosts = context.watch<HostProvider>().allHosts.where((h) => h.protocol == HostProtocol.ssh);
    return ListView(padding: const EdgeInsets.all(28), children: [
      const LText("MCP 服务", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      const LText("让本机 AI 客户端访问已连接的 SSH 主机。按主机配置权限后，复制客户端配置。",
        style: TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 20),
      SwitchListTile(contentPadding: EdgeInsets.zero,
        title: const LText("启用本机 MCP"),
        subtitle: LText(mcp.running ? LMessage("http://127.0.0.1:{0}/mcp", [mcp.port]) : "已停止"),
        value: mcp.running, onChanged: (value) => value ? mcp.start() : mcp.stop()),
      if (mcp.error != null) Text(mcp.error!, style: const TextStyle(color: Colors.redAccent)),
      if (mcp.running) Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
        icon: const Icon(Icons.copy, size: 16), label: const LText("复制客户端配置（含访问令牌）"),
        onPressed: () => Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert({
          'mcpServers': {'xterminal': {'type': 'http', 'url': 'http://127.0.0.1:${mcp.port}/mcp',
            'headers': {'Authorization': 'Bearer ${mcp.token}'}}}}))))),
      const SizedBox(height: 16),
      const LText("权限在退出应用后清除；每次启动服务都会生成新的地址和令牌。", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const Divider(height: 32),
      if (hosts.isEmpty) const LText("添加并连接 SSH 主机后，可在这里授权。"),
      for (final host in hosts) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(host.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4), LText(LMessage("{0}:{1}", [host.host, host.port]), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true,
            title: const LText("允许执行远程命令"),
            subtitle: const LText("命令具有该 SSH 用户的权限，不受下面的文件目录限制。"),
            value: mcp.grants[host.id]?.execute ?? false,
            onChanged: (v) => mcp.changeGrant(host.id, (g) => g.execute = v ?? false)),
          CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true,
            title: const LText("允许浏览和读取文件"), value: mcp.grants[host.id]?.files ?? false,
            onChanged: (v) => mcp.changeGrant(host.id, (g) { g.files = v ?? false; if (!g.files) g.write = false; })),
          if (mcp.grants[host.id]?.files == true) ...[
            TextFormField(key: ValueKey(host.id), initialValue: mcp.grants[host.id]?.root ?? '',
              decoration:  InputDecoration(labelText: tr(context, "允许访问的远程目录"), hintText: tr(context, "/home/user/project")),
              onChanged: (v) => mcp.changeGrant(host.id, (g) => g.root = v)),
            CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true,
              title: const LText("允许覆盖该目录内的已有文件"), value: mcp.grants[host.id]?.write ?? false,
              onChanged: (v) => mcp.changeGrant(host.id, (g) => g.write = v ?? false)),
          ],
        ]))),
    ]);
  }
}

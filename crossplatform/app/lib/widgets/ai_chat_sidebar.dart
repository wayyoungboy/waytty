import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/ai_provider_config.dart';
import '../models/chat_message.dart';
import '../providers/ai_chat_provider.dart';
import '../theme/app_theme.dart';

class AiChatSidebar extends StatefulWidget {
  final VoidCallback onClose;

  const AiChatSidebar({super.key, required this.onClose});

  @override
  State<AiChatSidebar> createState() => _AiChatSidebarState();
}

class _AiChatSidebarState extends State<AiChatSidebar> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<AiChatProvider>().send(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiChatProvider>();

    return Container(
      width: 340,
      color: AppColors.sidebar,
      child: Column(
        children: [
          _buildHeader(context, provider),
          if (provider.loadError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(provider.loadError!),
            ),
          if (!provider.configured) _buildUnconfiguredBanner(),
          Expanded(child: _buildMessageList(provider)),
          _buildInput(provider),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AiChatProvider provider) {
    final configured = provider.configuredProviders;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.smart_toy_outlined,
            size: 16,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          const LText(
            "AI 助手",
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (configured.isNotEmpty) ...[
            const SizedBox(width: 8),
            DropdownButton<AiProvider>(
              value: configured.contains(provider.activeProvider)
                  ? provider.activeProvider
                  : configured.first,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
              dropdownColor: AppColors.card,
              underline: const SizedBox(),
              isDense: true,
              items: configured
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                        _providerLabel(p),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (p) {
                if (p != null) {
                  context.read<AiChatProvider>().setActiveProvider(p);
                }
              },
            ),
          ],
          const Spacer(),
          if (provider.messages.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.clear_all,
                size: 16,
                color: AppColors.textSecondary,
              ),
              onPressed: provider.clear,
              tooltip: tr(context, "清空对话"),
            ),
          IconButton(
            icon: const Icon(
              Icons.close,
              size: 16,
              color: AppColors.textSecondary,
            ),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  String _providerLabel(AiProvider p) => switch (p) {
    AiProvider.anthropic => 'Anthropic',
    AiProvider.openai => 'OpenAI',
    AiProvider.gemini => 'Gemini',
  };

  Widget _buildUnconfiguredBanner() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const LText(
        "在设置 → AI Providers 中配置服务地址、模型和 API 密钥。",
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMessageList(AiChatProvider provider) {
    if (provider.messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: LText(
            "生成命令、解释报错、分析故障，或翻译终端输出。",
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: provider.messages.length,
      itemBuilder: (_, i) => _buildMessage(provider.messages[i]),
    );
  }

  Widget _buildMessage(ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.accent,
              child: Icon(
                Icons.smart_toy_outlined,
                size: 14,
                color: Colors.black,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : AppColors.card,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: msg.isStreaming && msg.content.isEmpty
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : MarkdownBody(
                      data: msg.content,
                      selectable: true,
                      sizedImageBuilder: (config) => Text(config.alt ?? tr(context, '[Image]')),
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                        code: const TextStyle(
                          color: AppColors.accent,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          backgroundColor: AppColors.bg,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: AppColors.bg,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.card,
              child: Icon(
                Icons.person,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInput(AiChatProvider provider) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              maxLines: 3,
              minLines: 1,
              decoration:  InputDecoration(
                hintText: tr(context, "输入问题…"),
                hintStyle: TextStyle(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onSubmitted: (_) =>
                  provider.configured && !provider.loading ? _send() : null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: provider.loading
                ? provider.stop
                : provider.configured
                ? _send
                : null,
            icon: Icon(
              provider.loading ? Icons.stop_circle_outlined : Icons.send,
              size: 18,
              color: AppColors.accent,
            ),
            tooltip: tr(context, provider.loading ? "停止生成" : "发送"),
          ),
        ],
      ),
    );
  }
}

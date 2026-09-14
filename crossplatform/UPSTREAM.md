# 上游与 waytty

跨平台基础采用 [YourSSH](https://github.com/YoursshLabs/yourssh)，MIT 许可。

- 固定来源提交：`832c44b8e7d76ff77b32159e547d281c18be24b1`
- 来源作者：Thang Nguyen / YourSSH contributors。
- 原始许可：本目录 `LICENSE`，各 packages 保留许可证与源码头。
- waytty 目标：XTerminal 风格和工作流的跨平台复刻，macOS 优先、Windows 与安卓平板后续；排除 RDP，VNC 暂不启用。
- 保留上游协议、平台适配和测试；修改 UI/组织与品牌，新增共享中文/英文、Telnet、笔记、连接中心工作流、本地 MCP、加密同步 RPC 与流式 AI 等。
- 上游自更新和自动安装脚本已禁用。云服务仅按用户配置运行。不读取 XTerminal 私有数据库。
- 内部 YourSSH Dart 包名以及既有本地存储标识保留，产品展示名为 waytty。

当前工具链 Flutter 3.47.2 / Dart 3.13.2，SDK tag 对应提交 `d3b14c876900e553bc736ca19295fc09e3853e8e`。

# 上游与 waytty

跨平台基础采用 [YourSSH](https://github.com/YoursshLabs/yourssh)，MIT 许可。

- 固定来源提交：`832c44b8e7d76ff77b32159e547d281c18be24b1`
- 来源作者：Thang Nguyen / YourSSH contributors。
- 原始许可：本目录 `LICENSE`，各 packages 保留许可证与源码头。
- waytty 目标：面向开发与运维的跨平台终端，macOS 优先、Windows 与安卓平板后续；排除 RDP，VNC 暂不启用。
- 保留上游协议、平台适配和测试；修改 UI/组织与品牌，新增共享中文/英文、Telnet、笔记、连接中心工作流、本地 MCP、加密同步 RPC 与流式 AI 等。
- 上游自更新和自动安装脚本已禁用。云服务仅按用户配置运行，不自动导入其他应用的数据。
- 产品名、应用标识、插件目录及同步接口使用 waytty 命名；保留 YourSSH 内部 Dart 包名、上游存储键和第三方版权说明。

当前工具链 Flutter 3.47.2 / Dart 3.13.2，SDK tag 对应提交 `d3b14c876900e553bc736ca19295fc09e3853e8e`。

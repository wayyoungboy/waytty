# waytty 架构

用户确定采用 Flutter 统一界面与共享核心，优先开发和维护效率。macOS 为当前验收平台，Windows 与 Android 平板为后续目标；排除 RDP，暂不启用 VNC。

## 分层

1. **Flutter 界面**：连接中心、分组和过滤、会话工作区、分屏、文件传输、监控、Markdown 笔记、命令库、AI、设置。桌面紧凑布局；Android 在宽度达到 900 时使用侧边导航，窄屏使用底部导航。
2. **共享核心**：Dart SSH/SFTP、Telnet、代理/跳板、端口转发、传输队列、终端解析、会话管理、同步加密、AI SSE、MCP 授权。核心协议不依赖系统 OpenSSH。
3. **原生适配**：macOS PTY、Windows ConPTY、Android 系统文件选择器；原生窗口、通知、菜单和快捷键通过插件/通道接入。QuickJS 是单独的 FFI 服务，macOS 构建时随应用打包。
4. **多语言**：共享 `waytty_l10n` 包，简体中文默认，English 可选；应用选择优先于系统语言。Flutter 的 Material/Cupertino 内置对话框和 macOS 菜单跟随选择。系统文件选择器、OS 权限弹窗、服务器与第三方错误文本仍可能使用系统或原始语言。

串口使用独立 `SerialConfig` / `SerialProfile` / `SerialSession implements AppSession`，不借用 SSH 主机、凭据或终端广播。桌面端每个端口由专用 Dart isolate 持有 native libserialport 句柄；Android 由 `SerialChannel` 调用 USB Host 驱动，权限请求和实际写入在原生层处理。字节通过带接收确认的通道传递，应用缓存有上限；底层设备/驱动的丢包无法仅靠应用计数证明不存在。

## 数据与连接

- 连接、分组、笔记、命令库与偏好保存在本地；密码留在进程内；手动粘贴并选择保存的私钥使用独立本地加密存储，重启后手动解锁。不读写系统钥匙串。SSH 新连接使用手动输入或已解锁的本地私钥，后台工具仅复用已认证连接。见 [手动认证](MANUAL_AUTH.md)。
- macOS bundle 标识与 Android application ID 统一为 `io.github.wayyoungboy.waytty`；插件位于 `~/.waytty/plugins`，生成的密钥与录制位于 `Documents/waytty`，笔记键为 `waytty.notes.v1`。早期开发包的数据需要[手动迁移](UPGRADING.md)。Dart 内部 YourSSH 包名保留。
- 主机密钥验证保留，不能自动信任未知/变更指纹。
- 终端就绪判断只被动观察 Shell 信号，不发送空回车探测。没有 bracketed-paste 就绪标记的 Shell 跳过自动 Shell 集成/模板注入，用户输入原样发送，避免反复执行空命令或干扰登录提示。
- 默认本地离线；新增统一邮箱账号云端模式（邮箱验证码验证、9–16 位登录密码、独立保险库密码）。账号备份通过客户端 AES-GCM 加密与服务端 RLS 隔离，显式保存/恢复连接和连接密码，修订号防覆盖。配置、边界和验收见 [CLOUD_ACCOUNT.md](CLOUD_ACCOUNT.md)。
- 独立账号 API 使用 SQLite（默认）或 MySQL，负责邮件验证、scrypt 密码哈希、会话和密文存储。客户端只配置 HTTPS 服务地址。旧同步码入口移除；扫码传输保留，实时共享暂时停用。
- 账号库保存邮箱、密码哈希、验证码 HMAC、会话令牌哈希和加密快照。服务端通过会话隔离账号，在事务内比较修订号。客户端会话和保险库密码只留在进程内，退出或重启需重新登录与解锁。
- 本地更改未上传时阻止直接拉取覆盖；修订号避免上传期间的新修改被误判为已同步。尚未实现完整的多端冲突合并与版本历史。
- AI 支持 OpenAI 兼容、Anthropic 和 Gemini 的流式协议，自定义 endpoint/model/key；中止请求会关闭客户端并丢弃迟到回复。
- 本机 MCP 默认关闭，仅监听 loopback，使用 Bearer 令牌以及按连接配置的命令/文件权限；只操作已连接 SSH。执行有超时及输出上限，文件访问有目录范围限制。

## 平台验收边界

- macOS：本机编译与运行，实际终端交互，隔离 SSH/SFTP 和 PostgreSQL 测试。
- Windows：保留原生工程与构建脚本，尚未实机编译验证；需验证 ConPTY、输入法、文件路径和 FFI 打包。
- Android 平板：共享语言与业务层、宽屏导航已实现，尚未 SDK/设备构建验证；需补全 Telnet 入口、存储授权、后台连接及触控/键盘验收。本地 shell 的能力受 Android 沙盒限制。

应用只读取自身数据与用户明确选择导入的文件，不自动扫描其他应用保存的连接与凭证。

## 已规划的扩展

- [AI 运维助手](plans/AI_OPERATIONS_ASSISTANT.md)：工具执行与授权由 waytty 管理，Agent 引擎可替换；Pi 与 Dart 原生调用方案先验证再选型。
- [串口调试](SERIAL.md)：基础实现已接入，平台和硬件验收范围见该文档；[原方案](plans/SERIAL_DEBUGGER.md)中的 ANSI、多编码、自动设备刷新和 AI 联动继续分阶段完善。

AI 运维工具执行与串口 AI 联动仍处于规划阶段，现有串口调试可独立使用。

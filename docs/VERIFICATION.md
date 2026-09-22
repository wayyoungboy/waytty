# 本机构建与验收记录

## 独立账号存储与版本文案（2026-09-17）

- 账号服务已替换为独立 Node.js API，SQLite 默认文件存储、MySQL 可选。两种数据库均通过 HTTP/数据库测试：注册令牌与密码绑定、OTP 单次消费和过期、持久化限流、会话撤销/过期、账号隔离、并发版本冲突和事务回滚。MySQL 使用临时隔离 9.3 实例，不访问既有数据库。
- 客户端已移除 Supabase SDK 和自动同步入口。旧模式回到本地，旧配置与本机连接保留；扫码传输保留，实时共享暂时停用。Flutter 静态分析无问题，全量 1,872 项测试通过、1 项 SSH fixture 跳过；1,406 条中英文资源和 310 个 Dart 文件本地化检查通过。
- 官网与中英文 README 统一显示 v0.0.1。已验证中文/英文切换、1440×1000 桌面和 390×844 手机视图，版本后无“开发版”字样，无横向溢出或控制台错误；40 个网站链接/资源检查通过。
- 官网本次文案验证使用已安装 Chrome 和内置 Playwright，原因：本轮未提供 Browser skill；无新增浏览器依赖。服务端依赖审计未发现已知漏洞。
- 未推送、部署或发送真实邮件。SMTP 与正式域名需要运营配置；未构建新的原生安装包。旧 SQL 仅作历史迁移参考，不再参与当前账号存储。

## 应用身份统一（2026-09-17）

- 全部 1,217 个源码文件完成命名检查；文件名、产品文案、原生应用标识、存储路径、插件提示、同步接口和 Swift 原型使用 waytty 命名。中英文 1,348 条资源校验通过，307 个 Dart 界面文件的本地化检查无发现。
- `script/check_crossplatform.sh`（启用隔离 SSH fixture）：1,889 项测试全部通过，Flutter 静态分析无问题。Swift 原型 14 项测试通过，临时 PostgreSQL 中的同步 RPC 权限与令牌隔离测试通过。
- 全量测试发现并修复已有 SSH 时序问题：在发送 exec / shell 请求前注册会话的退出状态监听，避免快速结束的命令在请求确认到达时丢失退出码。回环回归包含连续 20 次快速 exec 与 10 次快速结束的 shell。监控测试改为精确匹配 CPU 百分比，避免时间字符串造成误报。
- macOS 版本为 `0.0.1+2`，应用标识为 `io.github.wayyoungboy.waytty`。构建不会替换或重启正在运行的应用；早期开发包的数据需要按照[升级说明](UPGRADING.md)迁移。Windows、Android 及实际串口硬件的验收边界保持不变。

## 初始检查

环境：2026-09-13，macOS 26.6.2，Apple Silicon，Xcode 26.6，Flutter 3.47.2 / Dart 3.13.2。

- `flutter analyze --no-pub`：无问题。
- Flutter 全量测试（启用本机 SSH fixture）：1,754 项通过。
- QuickJS 原生运行时测试：4 项通过；桥接库包含 arm64 和 x86_64 架构。
- 999 条中英文共享文案通过完整性与占位参数校验。
- PostgreSQL 18 隔离 RPC 权限测试通过；临时数据库在验收后停止。
- macOS Release 构建成功；`codesign --verify --deep --strict` 通过。
- 实际 GUI：默认中文；切换 English 即时更新设置、连接中心与系统菜单；退出重新打开后仍为 English；验收后已恢复简体中文。
- 语言回归：英文系统首次启动仍默认中文，保存/恢复、快速连续选择、用户内容和动态参数保留；360/900/1280 宽度下语言选择器无溢出；连接分组长标题受宽度约束。
- SSH/SFTP：测试使用本机随机端口、临时密钥与沙盒文件目录；验证中文执行输出、stderr/exit code、MCP 输出限制/超时，以及中文文件名、二进制恢复传输、权限和重命名。
- AI 仅使用 HTTP/SSE fixture，未消耗真实 API；账号服务未部署，真实 SMTP 尚未联调。

可交付物：`dist/waytty.app`、`dist/waytty-macos.zip`。应用版本为 v0.0.1，完整功能与高保真验收范围见 PARITY.md。Windows/Android 尚未实机编译验收；包含 x86_64 代码不等于完成 Intel Mac 实机验收。

依赖的编译器告警和 CocoaPods/Swift Package Manager 迁移提示仍存在，没有隐藏这些上游告警；本项目 Flutter 分析结果为零问题。应用使用 ad-hoc 签名，尚未 Developer ID 签名/公证。

## 串口接入后的复验（2026-09-13）

- `WAYTTY_SSH_FIXTURE_PYTHON=/tmp/waytty-ssh-fixture-env/bin/python ./script/check_crossplatform.sh`：1,773 项测试全部通过（没有跳过），Flutter 静态分析无问题；包含原有真实 SSH/SFTP 回环测试。
- 其中新增串口专项 19 项：会话与设备独占、字节/中文/HEX、部分写入及停止、迟到打开/断线、缓存、配置损坏保留、中英文 UI，以及模拟 Android 原生通道的身份/权限取消/写入结果。
- 专项覆盖率记录：串口会话 121/142 行，Android Dart 通道 58/67 行，配置仓库 34/35 行。原生 Kotlin 和桌面 FFI 的硬件行为不计入这组模拟测试结论；UI 与其他原生分支未达到同样的覆盖率。
- 1,063 条中英文资源校验通过。串口入口默认中文，420 像素宽的英文配置页未出现溢出。
- macOS Release 应用已成功构建，在真实窗口打开「连接 → 串口」并枚举系统串口；截图保存在 `docs/screenshots/serial-zh.png`。
- 驱动所需 `automake` / `libtool` 已安装；串口依赖许可证纳入应用资源和发布包。桌面读写使用非阻塞 API；接收通道有逐批确认以限制积压。
- 本轮未打开用户物理串口、发送硬件字节或访问真实模型 API。真实 USB 芯片回环、控制线路和拔插、Windows 目标构建、Android Kotlin/USB 真机、ANSI/多编码与串口 AI 联动仍待后续。

详细使用方法与当前限制见 [SERIAL.md](SERIAL.md)。最终完整检查日志：`/tmp/waytty-serial-final-check.log`；发布构建日志：`/tmp/waytty-serial-release.log`。

串口版本已生成 `dist/waytty.app` 与约 32 MiB 的 `dist/waytty-macos.zip`，重新验证签名通过并已启动；应用停留在中文串口调试页。ZIP SHA-256：`60009966d0959ced579dae400c3cb6af8311e2dbb3a02a450103d21b746774ec`。

## SSH 首次提示符重复修复（2026-09-14）

- 复现原因：隐藏的 Shell 集成初始化完成后，DONE 标记的 CRLF 仍被写入终端，保留了旧提示符，又在下一行绘制新提示符。
- 修复只消费初始化完成标记紧邻的一个换行，并重绘原提示符所在的逻辑行；根据终端实际软换行状态清除续行，保留登录信息及后续用户命令输出。超时或异常大量输出仍走原有保留输出路径。
- 回归覆盖 80/20 列提示符、切换到更短提示符、CRLF 跨包、协议输出所有单次分包位置，以及正常回车/命令输出。输出门控文件覆盖率 64/64 行。
- 全量检查 1,857 项测试通过（启用隔离 SSH/SFTP 回环 fixture），静态分析无问题；macOS Release 构建及严格签名检查通过。日志：`/tmp/waytty-prompt-check.log`、`/tmp/waytty-prompt-release.log`。
- 修复版单独保存为 `dist/updates/ssh-prompt/waytty.app` 和同目录 `waytty-macos.zip`；没有替换或重启正在使用的旧版，现有会话继续运行。本次验证使用本地模拟输出与回环服务，没有操作用户远程主机。
- 修复版 ZIP SHA-256：`4a6d838ad4ea113680b4f763b2026e5ef198e20957cb1a152ac987336bec3d8d`。

## 中文界面全局复查（2026-09-14）

- 从扩展管理页开始复查：内置扩展的动态名称/说明、桌面和移动端通用标签、终端侧栏、排序与导入选项、工具页、文件选择标题、表单验证、连接/传输/同步状态、通知和错误提示。补齐 261 条中英文资源，总计 1,324 条，默认中文与用户已保存的语言选择保持原有行为。
- 新增 `crossplatform/app/tool/audit_l10n.dart`，已接入 `script/check_crossplatform.sh`。语法扫描覆盖主应用和三个内置扩展的 305 个 Dart 文件，检查直接界面文案、内置扩展元数据及已接入的翻译调用；当前无发现。另核对 53 个原生菜单文案均已进入资源表。通过变量或服务传入的文案仍需结合控件测试和人工核对，不能仅靠 ARB 键数量判断覆盖率。
- 7 项专项控件回归通过：扩展元数据切换语言、侧栏标题与关闭提示、用户自定义主机/脚本扩展名称保留、移动端导航、运维/Web 工具导航，以及工具错误与原始解码内容的区分。内嵌浏览器使用测试平台替身，未发起浏览器网络请求。英文侧栏的文字溢出一并修复。
- macOS Release 构建和严格签名检查通过；修复版包含之前的 SSH 首次提示符修复。应用与 ZIP 单独保存为 `dist/updates/localization-audit/waytty.app` 和同目录 `waytty-macos.zip`，没有替换或重启用户正在运行的版本。
- 一次构建并行期间的全量测试出现 SSH 回环退出码波动（预期 7、实际 -1）；结束构建后单独复验通过。本轮没有操作用户的远程主机。
- 最终完整检查通过：主应用 1,864 项测试、快捷命令扩展 6 项测试全部通过，Flutter 静态分析无问题，语法扫描与中英文资源/占位符校验通过。
- ZIP SHA-256：`22a9044115fac6fa851e1d590051a30e419663b825518ffec974233ecd835695`。构建日志：`/tmp/waytty-l10n-release.log`；完整检查：`/tmp/waytty-l10n-final-check.log`；扩展测试：`/tmp/waytty-l10n-plugin-tests.log`。

## 分屏边界线修复（2026-09-14）

- 左右、上下和四宫格布局的五处分隔线统一使用 `#808080`、2 个逻辑像素的显式线宽与占位宽度；单窗格不增加分隔线，空窗格使用相同边界。
- 根据主题背景计算，新线条与 44 个内置终端主题背景的最低对比度为 3.05:1；截图所用 Dracula 背景的对比度从 1.01:1 提升至 3.61:1。
- 现有布局状态、本地终端窗格及主题测试共 21 项通过；Flutter 静态分析无问题，305 个 Dart 文件的多语言检查无发现。本轮未添加测试，未重新执行全量测试，也未连接用户主机进行截图验收。
- macOS Release 构建与严格签名检查通过。更新包为 `dist/updates/split-borders/waytty.app` 和同目录 `waytty-macos.zip`；保留此前中文和 SSH 提示符修复，没有替换或重启正在运行的应用。
- ZIP SHA-256：`1e6e70c15314744e8a433147ad96eeef20694f86a95adbdb3bf3c513203cf0fc`。构建日志：`/tmp/waytty-split-borders-release.log`。

## 会话工作区监控接入（2026-09-14）

- 终端工具栏新增可见的「监控」入口及跟随会话的侧栏，平板终端更多菜单复用同一监控界面；主机列表原有弹窗保留。新增负载、交换内存、网卡速率与 CPU/内存趋势，默认中文；资源总数 1,341 条。
- 采集只复用已有 SSH 连接，单请求限制 8 秒/512 KiB，不经过交互式终端或命令改写插件。暂停、关闭、断线、换主机时取消后续轮询并忽略迟到结果；采集失败时显示错误，不再将旧数据标为实时。旧网络浮层的关闭后仍采集、慢请求重叠和迟到数据问题一并修复。
- 全量检查 1,879 项测试通过，Flutter 分析无问题，306 个 Dart 文件的多语言检查无发现。包括真实本机 SSH 回环上的监控 exec、UTF-8、返回码、输出上限及超限后连接仍可用；没有操作用户远程主机或重启正在使用的应用。
- 42 项监控相关测试通过。行覆盖率：系统模型与系统/防火墙采集器 100%，监控主体 95.5%，侧栏 88.9%，网络采集器 88.9%，网络浮层 90.9%。这是相关文件的行覆盖率，不是整个应用或远端平台的实机覆盖率。
- 使用模拟指标和本机字体渲染检查 340 逻辑像素宽度，中文截图为 `docs/screenshots/monitoring-zh-fixture.png`；中英文标签、长主机名、网络首次采样与速率、断线、暂停及切换主机均有控件回归。尚未在 Linux 真机对照读数，也未编译 Windows/Android 安装包。
- macOS Release 构建和严格签名检查通过。独立更新包为 `dist/updates/monitoring/waytty.app`、同目录 `waytty-macos.zip`，包含之前的中文、提示符和分屏边界修复。
- ZIP SHA-256：`67426c7a0b8fac1a819a665139bc9620b59a690149dcf201a8fc5ce76b0f650b`。完整检查日志：`/tmp/waytty-monitor-full-check.log`；专项覆盖率：`/tmp/waytty-monitor-coverage.log`；构建：`/tmp/waytty-monitor-release.log`。

## CPU 各核心明细（2026-09-15）

- CPU 下拉框支持总体、全部逻辑核心和指定核心；全部核心使用有界高度、按需构建的滚动卡片，单核保持独立趋势。每次采样同时读取 `/proc/stat` 的总体及各核心行，按 CPU ID 匹配两次读数并数值排序；切换视图不新增 SSH 请求。
- 新增 10 项回归覆盖不连续/乱序核心编号、guest 重复计数、上线/下线、计数重置/停滞、坏行、旧版总体样本、中文/英文选择、128 核滚动，以及完整侧栏中的切换和请求数量。新上线或无有效差值的核心不显示虚假的 0%；所选核心下线时回到总体。
- 全量 1,889 项测试通过，静态分析无问题，307 个 Dart 文件的翻译检查无发现；中英文资源 1,348 条。两条生产采样的 grep 表达式也通过本机样本验证，均包含总体与各核心并排除其他 `/proc/stat` 行。
- 29 项相关测试通过并收集覆盖率：系统模型 160/160 行、采集器 21/21 行、CPU 显示组件 116/116 行。随后统一下拉框字体，并重新通过两种实际控件渲染测试与静态分析。
- 340 逻辑像素侧栏的模拟数据截图：`docs/screenshots/cpu-all-cores-zh-fixture.png`、`docs/screenshots/cpu-single-core-zh-fixture.png`。未访问用户远端主机，未重启现有会话；Linux 真机读数、Windows/Android 构建仍沿用上一节的未验收范围。
- macOS Release 构建和严格签名检查通过。更新版为 `dist/updates/cpu-cores/waytty.app`、同目录 `waytty-macos.zip`。ZIP SHA-256：`deb8e229487b2a7a641d96e526bfa89c82a62eb38fafe10980144fda2335abf9`。
- 日志：`/tmp/waytty-cpu-cores-full-check.log`、`/tmp/waytty-cpu-cores-coverage.log`、`/tmp/waytty-cpu-preview.log`、`/tmp/waytty-cpu-cores-release.log`。

# waytty

[源码](https://github.com/wayyoungboy/waytty) · [问题反馈](https://github.com/wayyoungboy/waytty/issues) · [功能进展](docs/PARITY.md) · [官网部署](website/README.md)

**[下载 v0.0.1 开发版](https://github.com/wayyoungboy/waytty/releases/tag/v0.0.1)** · [官网](https://wayyoungboy.github.io/waytty/)

macOS 12 及以上，Universal 安装包同时支持 Apple Silicon 和 Intel。当前使用 ad-hoc 签名，尚未做 Developer ID 签名或 Apple 公证；系统可能阻止首次打开，请先核对来源与 SHA-256。Release 同时提供源码、串口依赖对应源码及校验文件。

waytty 是面向开发与运维的跨平台终端客户端，采用 **Flutter 界面 + Dart 共享协议与业务核心**。当前优先交付 macOS，工程同时保留 Windows 和 Android 平板入口。**RDP 不在范围内，VNC 暂不启用。**

首次启动默认简体中文，设置中的「界面语言」可切换 English，选择会保存并在重启后恢复。界面、工具插件及 macOS 菜单共用翻译资源；主机名、文件名、笔记、命令和服务器输出保持原文。

这是可运行的开发版本，部分功能仍需实机验收；功能状态见 [docs/PARITY.md](docs/PARITY.md)。从早期开发包升级前，请阅读[数据迁移说明](docs/UPGRADING.md)。

串口调试入口位于「连接 → 串口」；安卓位于连接页右上角的串口图标。支持参数配置、配置保存、独立标签、文本/HEX 收发、记录导出、定时/文件发送及 DTR/RTS/BREAK 控制。详见 [串口使用与验收](docs/SERIAL.md)。

## 界面预览

连接管理：默认中文，支持分组、收藏、最近访问和搜索。以下是空白演示工作区，未包含真实服务器资料。

![waytty 中文连接管理界面](docs/screenshots/connections-zh.png)

串口调试：在同一应用中配置设备、波特率、数据位、校验位和流控。

![waytty 串口调试入口](docs/screenshots/serial-zh.png)

Linux 主机监控支持「总体」「全部核心」「单个核心」切换。下图由真实 Flutter 界面使用测试数据渲染。

<p>
  <img src="docs/screenshots/cpu-all-cores-zh-fixture.png" alt="CPU 全部核心及趋势" width="280">
  <img src="docs/screenshots/cpu-single-core-zh-fixture.png" alt="CPU 单核心及趋势" width="280">
</p>

## 运行与检查

需要 Flutter 3.47.2 / Dart 3.13.2，macOS 构建需要 Xcode、CocoaPods，以及串口库构建依赖 `automake`、`libtool`（Homebrew）。可通过 `WAYTTY_FLUTTER` 指定 Flutter 可执行文件。

```sh
./script/build_and_run.sh --verify  # 编译、签名、启动检查
./script/build_and_run.sh --release # Release 应用和 zip，并启动
./script/check_crossplatform.sh    # 翻译校验、静态分析、自动化测试
```

产物为 `dist/waytty.app` 和 `dist/waytty-macos.zip`。应用目前使用本机 ad-hoc 签名，未作 Developer ID 签名或公证。

真实 SSH/SFTP 测试使用隔离的本机服务，不访问已保存的服务器：

```sh
python3 -m venv /tmp/waytty-ssh-fixture
/tmp/waytty-ssh-fixture/bin/pip install asyncssh==2.21.1
WAYTTY_SSH_FIXTURE_PYTHON=/tmp/waytty-ssh-fixture/bin/python ./script/check_crossplatform.sh
```

未设置该变量时，真实 SSH/SFTP fixture 测试跳过。Supabase 权限测试在临时 PostgreSQL 数据库中执行 `crossplatform/supabase/tests/access_control.sql`；不会连接远程 Supabase。

Windows 构建入口为 `script/build_windows.ps1`，Android 为 `script/build_android.sh`；需要相应系统/SDK，当前未通过目标系统构建验收。

## 工程

- `crossplatform/app`：主应用和平台工程。
- `crossplatform/packages/waytty_l10n`：共享中英文 ARB 资源和语言设置。
- `crossplatform/packages`：SSH、终端、PTY、脚本及工具插件。
- `crossplatform/supabase`：自托管加密同步所需迁移和访问控制测试。
- `docs/ARCHITECTURE.md`：架构、平台边界与数据说明。
- `docs/LOCALIZATION.md`：添加和维护翻译。

根目录的 SwiftPM 工程是早期参考原型，不是主应用；保留在 `script/build_swift_prototype.sh` 中，不影响 Flutter 构建入口。

本项目基于 MIT 许可的 YourSSH 修改，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [crossplatform/UPSTREAM.md](crossplatform/UPSTREAM.md)。第三方许可证、版权和来源说明随源码保留。

## 官网与开源检查

官网源码在 `website/`，默认中文，可切换 English；不依赖 npm、外部字体或统计服务。运行 `python3 script/build_site.py` 后使用 `python3 -m http.server 8765 --directory dist/site` 本地预览。

`.github/workflows/pages.yml` 在推送到 `main` 后检查源码隐私、构建官网并部署 GitHub Pages。首次需要在仓库 **Settings → Pages → Source** 选择 **GitHub Actions**，详见 [官网部署说明](website/README.md)。部署后的默认地址为 `https://wayyoungboy.github.io/waytty/`；此处不表示站点已经上线。

发布前运行 `python3 script/check_privacy.py --history`，需安装 Gitleaks。检查含源码、未忽略的新文件和历史提交；已审核的公开测试夹具按精确内容放行。检查范围及旧开发安装包的限制见 [隐私检查记录](docs/PRIVACY_REVIEW.md)。

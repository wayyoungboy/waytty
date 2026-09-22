# 发布与重新构建

## macOS 0.0.2

从 `v0.0.2` 标签源码，使用 Flutter 3.47.2 / Dart 3.13.2、Xcode 26.6（GitHub macos-26 构建环境）、CocoaPods，以及 automake、libtool 构建：

```sh
WAYTTY_FLUTTER=/path/to/flutter/bin/flutter ./script/package_macos_release.sh
python3 script/assemble_release.py
```

脚本只构建和打包，不会停止或启动已有 waytty。安装包是 macOS 版本，ad-hoc 签名，未做 Developer ID 签名或 Apple 公证。

`waytty-0.0.2-macos-universal.zip` 适用于 macOS 12 及以上，包含 Apple Silicon 和 Intel 两种架构。应用版本为 `0.0.2`，构建号为 `3`。Release 的 `SHA256SUMS.txt` 可用于校验下载；解压后将 `waytty.app` 放入 Applications。从早期开发包升级前，请先阅读[数据迁移说明](UPGRADING.md)。

在公开发布前，使用中性路径下的源码、Flutter SDK 和 `PUB_CACHE` 构建，再检查所有二进制和资源的字符串，避免绝对路径泄露个人目录。不要上传本地 `dist/updates/` 中的旧开发包。

## 第三方串口源码与重新链接

Release 附带 `waytty-0.0.2-serial-sources.zip`，包含 Dart libserialport 0.3.0+1、Flutter 封装 0.6.0、macOS CocoaPod 使用的 libserialport C 源码、podspec 和构建说明。主应用完整源码随标签及源码附件提供。

修改 Dart 串口库时，在 `crossplatform/app/pubspec_overrides.yaml` 的 `dependency_overrides` 中添加 `libserialport` 指向解压后的 Dart 包路径；如需修改 Flutter 封装，同样添加 `flutter_libserialport` 的路径覆盖。然后执行上述构建命令。应用中的既有路径覆盖仍需保留。

修改 C 库时，可在 `macos/Podfile` 的 Runner target 中将 `libserialport` 指向修改后的 podspec 或本地路径，重新执行 `pod install` 并构建。动态库在应用 Frameworks 中独立打包，构建脚本使用本地 ad-hoc 签名，不要求发布者私钥。编译进 Dart AOT 的库可通过完整应用源码重新构建。

保留各组件的许可文本与源码说明。`THIRD_PARTY_NOTICES.md` 列出组件版本和来源；最终上传前生成 SHA-256 校验文件。

## 自动验证与发布附件

`.github/workflows/macos-release.yml` 在拉取请求、main 更新及版本标签上验证，固定 Flutter 3.47.2 的源码提交，执行全量回归（含本机 SSH/SFTP）、源码隐私检查和 Universal 构建。只有验证成功才上传 `waytty-macos-release` 工件；工作流不自动公开 Release。

`assemble_release.py` 核对包版本、应用标识、签名、两种架构、个人构建路径和包内符号链接，生成应用 ZIP、完整源码、串口对应源码、`BUILD_INFO.txt` 及 `SHA256SUMS.txt`。构建信息记录源码提交及工具版本，附件发布前仍需核对其提交与标签。

从 v0.0.1 升级请在 GitHub 发布页手动下载 v0.0.2。v0.0.2 在“设置 → 更新”提供手动检查；检查只在用户操作时访问 GitHub。ZIP 下载和打开不代表替换安装已完成，请退出正在使用的 waytty 后将解压出的应用移入“应用程序”。不会关闭现有 SSH 会话或自动替换正在运行的应用。

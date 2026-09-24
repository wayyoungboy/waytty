# 发布与重新构建

## 0.0.3

[v0.0.3 发布页](https://github.com/wayyoungboy/waytty/releases/tag/v0.0.3) 已公开。标签 `v0.0.3` 指向构建提交 `d7e9cd1def78ca2b41b3f663d9b9cde8fa0e5fee`，应用版本 `0.0.3`，构建号 `4`（`crossplatform/app/pubspec.yaml`：`0.0.3+4`）。

- **macOS**：由 `.github/workflows/macos-release.yml` 在标签上验证并构建 Universal ZIP（macOS 12+，arm64 + x86_64），产出应用 ZIP、完整源码、串口对应源码和 `BUILD_INFO.txt`。ad-hoc 签名，未做 Developer ID 签名或 Apple 公证。
- **Windows**：`windows-android.yml` 产出便携 `waytty-0.0.3-windows-x64.zip`（无 Inno Setup / MSIX），附 `BUILD_INFO-windows.txt`。**尚未完成目标设备验收。**
- **Android**：**调试签名预览版**（`BUILD_INFO-android.txt` 记录 `signing=debug-keystore-fallback`）。**不可用于生产**；与未来正式签名包**无法原地升级**，届时可能需要先卸载再安装（卸载前请导出连接备份）。**尚未完成目标设备验收。**

标签触发的 `draft-release` 任务先把 Windows + Android 附件挂到草稿，macOS 工件随后手工上传；合并后的 `SHA256SUMS.txt` 覆盖全部其他附件。草稿经核对后由维护者公开。

| 附件 | SHA-256 |
| --- | --- |
| `waytty-0.0.3-macos-universal.zip` | `b411ed642f13f96d0d63bd9673e887e187983622231a98c33aaf75a3bc9d0a7f` |
| `waytty-0.0.3-source.zip` | `d1de2bd10d75e6f37a237274d3139e760c0a83d08e614fbfdf84411028da6406` |
| `waytty-0.0.3-serial-sources.zip` | `f8793863f21a09cc8d62f3261ef09463991c7d798d472812c83c06eefe1484c4` |
| `waytty-0.0.3-windows-x64.zip` | `f82d58057a6b6bca0caaeba66b6f40f3378749adcf7bec42999425b0989fc194` |
| `waytty-0.0.3-android-universal.apk` | `28db6c3db7a4726b53d00a48b5d91c732ccd00c3740e66c2da33ac3a0d8f7755` |
| `waytty-0.0.3-android-arm64-v8a.apk` | `745686a502da2a0c1e5f916590b97aac2263b6b378e634a5f55b904676c83def` |
| `waytty-0.0.3-android-armeabi-v7a.apk` | `2ac6038c70a773f40f156f5cce4cb2b907a855d43b8b2a3bf21eae52027274b7` |
| `waytty-0.0.3-android-x86_64.apk` | `bcf7ed5238d3dae3a37bfa831a7ee72b0b8f90b1598c87d7a5d8a79211e959b4` |
| `waytty-0.0.3-android.aab` | `4402e9b9ffcd89cf954a2a01877a136d8e37548bbdcbc4d0827dd8b89aff28a7` |
| `BUILD_INFO.txt` | `e2314163f1ac2ca6bc8c28c3405c810530301ff831c98bccf932cbe3c95aa08f` |
| `BUILD_INFO-windows.txt` | `472942de3e133929c4096cdd8ac86f6a31a8e0fff7ac8bc5fdee3edc1e6a7a5d` |
| `BUILD_INFO-android.txt` | `678c90ab8bf86088aef19078c578b01d96b9522e5efe6b470c61efaf72971657` |
| `SHA256SUMS-windows.txt` | `abb0fa3360eb3c1b58d849d52fc68447f4a334a43bc1e3ed211239fcf3f60344` |
| `SHA256SUMS-android.txt` | `767c45a6eeafc478bd932e61982cebf6b9d04da6c2626cdf0e53d78669fa9e74` |

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

修改 C 库时，先在附件的 `libserialport-c` 中执行 `./autogen.sh && ./configure`，生成配置头文件。然后在 `macos/Podfile` 的 Runner target 中添加 `pod 'libserialport', :path => '/path/to/libserialport-c'`，重新执行 `pod install` 并构建。附件保留完整 C 源码与构建脚本，打包时核对实际编译的 C 文件与对应上游标签一致。动态库在应用 Frameworks 中独立打包，构建脚本使用本地 ad-hoc 签名，不要求发布者私钥。编译进 Dart AOT 的库可通过完整应用源码重新构建。

保留各组件的许可文本与源码说明。`THIRD_PARTY_NOTICES.md` 列出组件版本和来源；最终上传前生成 SHA-256 校验文件。

## 自动验证与发布附件

`.github/workflows/macos-release.yml` 在拉取请求、main 更新及版本标签上验证，固定 Flutter 3.47.2 的源码提交，执行全量回归（含本机 SSH/SFTP）、源码隐私检查和 Universal 构建。只有验证成功才上传 `waytty-macos-release` 工件；工作流不自动公开 Release。

`assemble_release.py` 核对包版本、应用标识、签名、两种架构、个人构建路径和包内符号链接，生成应用 ZIP、完整源码、串口对应源码、`BUILD_INFO.txt` 及 `SHA256SUMS.txt`。构建信息记录源码提交及工具版本，附件发布前仍需核对其提交与标签。

从 v0.0.1 升级请在 GitHub 发布页手动下载 v0.0.2。v0.0.2 在“设置 → 更新”提供手动检查；检查只在用户操作时访问 GitHub。ZIP 下载和打开不代表替换安装已完成，请退出正在使用的 waytty 后将解压出的应用移入“应用程序”。不会关闭现有 SSH 会话或自动替换正在运行的应用。


## Windows / Android CI 打包

`.github/workflows/windows-android.yml` 在拉取请求、`main` 推送、`workflow_dispatch` 以及 `v*` 标签上构建：

- **Windows**（`windows-latest`）：固定 Flutter 3.47.2，先用 CMake 编译 `qjsbridge.dll`，再 `flutter build windows --release`，产出便携 ZIP `waytty-<ver>-windows-x64.zip` 与 `SHA256SUMS-windows.txt`。当前**不**自动生成 Inno Setup / MSIX 安装包。
- **Android**（`ubuntu-latest`）：固定 Flutter 3.47.2，产出分 ABI APK（armeabi-v7a / arm64-v8a / x86_64）、universal APK 与 AAB，附 `SHA256SUMS-android.txt`。若配置了仓库密钥 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`，则按 `android/key.properties` 做正式签名；否则回退 debug 签名，并在构建摘要中给出警告，**不得**当作生产发布物。0.0.3 的 Android 包明确标注为**调试签名预览版**：不可用于生产；与未来正式签名包无法原地升级，届时可能需要先卸载再安装。

本地入口：

```powershell
# Windows（需 VS 2022+ C++、CMake、Flutter 3.47.2）
./script/build_windows.ps1
```

```sh
# Android（需 Android SDK / NDK、JDK 17+、Flutter 3.47.2）
./script/build_android.sh
```

`v*` 标签会额外跑 `draft-release` 任务，把 Windows + Android 工件挂到**草稿** Release；工作流不会自动公开 Release，也不会在 PR/`main` 上创建发布。目标设备验收、USB 串口实机验收与正式签名发布仍需人工确认。


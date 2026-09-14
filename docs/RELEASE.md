# 发布与重新构建

## macOS 0.0.1

从 `v0.0.1` 标签源码，使用 Flutter 3.47.2 / Dart 3.13.2、Xcode 26.6、CocoaPods，以及 automake、libtool 构建：

```sh
WAYTTY_FLUTTER=/path/to/flutter/bin/flutter ./script/package_macos_release.sh
```

脚本只构建和打包，不会停止或启动已有 waytty。安装包是 macOS 开发版，ad-hoc 签名，未做 Developer ID 签名或 Apple 公证。

在公开发布前，使用中性路径下的源码、Flutter SDK 和 `PUB_CACHE` 构建，再检查所有二进制和资源的字符串，避免绝对路径泄露个人目录。不要上传本地 `dist/updates/` 中的旧开发包。

## 第三方串口源码与重新链接

Release 附带 `waytty-0.0.1-serial-sources.zip`，包含 Dart libserialport 0.3.0+1、Flutter 封装 0.6.0、macOS CocoaPod 使用的 libserialport C 源码、podspec 和构建说明。主应用完整源码随标签及源码附件提供。

修改 Dart 串口库时，在 `crossplatform/app/pubspec_overrides.yaml` 的 `dependency_overrides` 中添加 `libserialport` 指向解压后的 Dart 包路径；如需修改 Flutter 封装，同样添加 `flutter_libserialport` 的路径覆盖。然后执行上述构建命令。应用中的既有路径覆盖仍需保留。

修改 C 库时，可在 `macos/Podfile` 的 Runner target 中将 `libserialport` 指向修改后的 podspec 或本地路径，重新执行 `pod install` 并构建。动态库在应用 Frameworks 中独立打包，构建脚本使用本地 ad-hoc 签名，不要求发布者私钥。编译进 Dart AOT 的库可通过完整应用源码重新构建。

保留各组件的许可文本与源码说明。`THIRD_PARTY_NOTICES.md` 列出组件版本和来源；最终上传前生成 SHA-256 校验文件。

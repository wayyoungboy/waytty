# Third-party notices for waytty

waytty is an independently maintained application based on the MIT-licensed YourSSH project. The upstream authors' copyright and license notices are preserved below and in the source tree. No saved user data is included.

## YourSSH

Source: https://github.com/YoursshLabs/yourssh
Revision: 832c44b8e7d76ff77b32159e547d281c18be24b1
Copyright (c) 2025 Thang Nguyen. MIT License.
The complete license is preserved in crossplatform/LICENSE and bundled as UPSTREAM-LICENSE.txt.

## Vendored components

- dartssh2: license preserved in crossplatform/packages/dartssh2/LICENSE.
- xterm.dart: license preserved in crossplatform/packages/xterm/LICENSE.
- flutter_pty: license preserved in crossplatform/packages/flutter_pty/LICENSE.
- QuickJS: Copyright (c) 2017–2021 Fabrice Bellard and Charlie Gordon; MIT. Full license preserved in crossplatform/packages/yourssh_script_engine/native/QUICKJS-LICENSE.txt and source headers.
- YourSSH plugin API, script engine and included tools: covered by the upstream YourSSH license unless otherwise noted in their source files.
- Bundled terminal fonts: copyright and licenses are retained in crossplatform/app/assets/fonts/licenses. Source references: https://github.com/powerline/fonts and https://github.com/ryanoasis/nerd-fonts. Individual font licensing differs; consult the corresponding license text.

Flutter/Dart and resolved package licenses are collected by Flutter in its generated NOTICES asset. The macOS bundle additionally includes this document and a third-party-licenses directory. Source provenance and license headers are retained in the source tree. This notice does not replace the individual license terms.

## Serial transports

- flutter_libserialport 0.6.0: MIT, https://github.com/jpnurmi/flutter_libserialport.
- libserialport Dart 0.3.0+1: LGPL-3.0-or-later, https://github.com/jpnurmi/libserialport.dart. The unmodified package version and checksum are pinned in `crossplatform/app/pubspec.lock`.
- Native libserialport: LGPL-3.0-or-later, https://sigrok.org/wiki/Libserialport. The macOS CocoaPod resolves 0.1.1 (source revision `348a6d353af8ac142f68fbf9fe0f4d070448d945`); see `crossplatform/app/macos/Podfile.lock` and the installed podspec. The framework is bundled separately from the application executable.
- usb-serial-for-android 3.11.0: MIT, Copyright Google Inc., Mike Wakerly and contributors, https://github.com/mik3y/usb-serial-for-android/tree/3.11.0. Android only; used through waytty's own USB Host channel.

License texts are retained in `crossplatform/app/assets/serial-licenses/` and included in the application. For redistribution, retain the matching library sources and rebuild/relink materials for the LGPL components, including the Dart dependency compiled into the Flutter application; the Flutter wrapper's MIT license does not replace these obligations. macOS distribution here is a local development build, signed ad hoc without hardened library validation. Public-release packaging and corresponding-source delivery remain a separate release gate.

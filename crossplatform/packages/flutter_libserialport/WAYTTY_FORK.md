# waytty fork notes

Upstream: [flutter_libserialport 0.6.0](https://github.com/jpnurmi/flutter_libserialport).

Change vs upstream: replace removed `jcenter()` with `mavenCentral()` in
`android/build.gradle` so Android release builds work with Gradle 9 / AGP 9
(Flutter 3.47.x). Desktop (Windows/macOS/Linux) behavior is unchanged.

Android runtime serial I/O in waytty still uses the app's Kotlin
`SerialChannel` + `usb-serial-for-android`; this plugin is retained because
it is declared for all platforms and desktop serial depends on it.

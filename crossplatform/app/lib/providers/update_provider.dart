import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/services/update_service.dart';

/// Drives the in-app update flow: debounced launch check, periodic/focus
/// re-checks, manual check, download, and install hand-off. Surfaces state
/// to the banner and Settings.
class UpdateProvider extends ChangeNotifier {
  UpdateProvider(
    this._service, {
    required this.currentVersion,
    this.enabled = true,
    this.automaticChecks = false,
    DateTime Function()? now,
    this.checkInterval = const Duration(hours: 6),
  }) : _now = now ?? DateTime.now;

  static const _lastCheckKey = 'last_update_check';
  static const _dismissedKey = 'update_dismissed_version';
  static const _minInterval = Duration(hours: 24);

  final UpdateService _service;
  final String currentVersion;
  final bool enabled;
  final bool automaticChecks;
  bool _disposed = false;
  bool _checkInFlight = false;
  bool _installInFlight = false;
  final DateTime Function() _now;

  /// How often the periodic re-check ticks. Ticks are still debounced to
  /// 24h by [checkForUpdates], so GitHub is hit at most ~once per day.
  final Duration checkInterval;

  Timer? _periodicTimer;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  AppRelease? _latestRelease;
  AppRelease? get latestRelease => _latestRelease;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _dismissedVersion;

  bool get showBanner =>
      _status == UpdateStatus.available &&
      _latestRelease != null &&
      _latestRelease!.version != _dismissedVersion;

  /// Checks GitHub for a newer stable release. Auto checks (`manual == false`)
  /// are skipped if the last check was under 24h ago; manual checks always run.
  Future<void> checkForUpdates({bool manual = false}) async {
    if (!enabled ||
        _disposed ||
        (!manual && !automaticChecks) ||
        _checkInFlight ||
        _installInFlight) {
      return;
    }
    _checkInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _dismissedVersion ??= prefs.getString(_dismissedKey);
      if (!manual) {
        final last = prefs.getInt(_lastCheckKey);
        if (last != null) {
          final elapsed = _now().difference(
            DateTime.fromMillisecondsSinceEpoch(last),
          );
          if (!elapsed.isNegative && elapsed < _minInterval) return;
        }
      }
      _status = UpdateStatus.checking;
      _errorMessage = null;
      _notify();
      final release = await _service.fetchLatestRelease();
      if (_disposed) return;
      await prefs.setInt(_lastCheckKey, _now().millisecondsSinceEpoch);
      if (_disposed) return;
      _latestRelease = release;
      _status = _service.isNewerVersion(currentVersion, release.version)
          ? UpdateStatus.available
          : UpdateStatus.upToDate;
    } on UpdateException catch (e) {
      if (_disposed) return;
      _status = UpdateStatus.error;
      _errorMessage = e.message;
    } catch (e) {
      if (_disposed) return;
      _status = UpdateStatus.error;
      _errorMessage = 'Could not check for updates: $e';
    } finally {
      _checkInFlight = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Re-checks for updates while the app stays running, so a release
  /// published after launch still reaches the notification bell. Safe to
  /// call more than once; the previous timer is replaced.
  void startPeriodicChecks() {
    if (!enabled || !automaticChecks || _disposed) return;
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(checkInterval, (_) => checkForUpdates());
  }

  @override
  void dispose() {
    _disposed = true;
    _periodicTimer?.cancel();
    super.dispose();
  }

  /// Downloads the matching artifact and hands it to the OS installer.
  /// Opens the Releases page when no asset matches the current OS/arch.
  /// Download or launch failures remain visible so the user can retry.
  Future<void> downloadAndInstall() async {
    if (!enabled || _disposed || _installInFlight || _checkInFlight) return;
    final release = _latestRelease;
    if (release == null ||
        !_service.isNewerVersion(currentVersion, release.version)) {
      return;
    }
    _installInFlight = true;
    try {
      final asset = _service.assetForPlatform(
        release,
        os: _service.currentOs(),
        arch: _service.currentArch(),
      );
      if (asset == null) {
        await _openReleasePage(release);
        return;
      }
      _status = UpdateStatus.downloading;
      _downloadProgress = 0;
      _errorMessage = null;
      _notify();
      final file = await _service.downloadAsset(
        asset,
        onProgress: (p) {
          if (_disposed) return;
          _downloadProgress = p;
          _notify();
        },
      );
      if (_disposed) return;
      await _service.launchInstaller(file);
      if (_disposed) return;
      _status = UpdateStatus.readyToInstall;
    } on UpdateException catch (e) {
      if (_disposed) return;
      _status = UpdateStatus.error;
      _errorMessage = e.message;
    } catch (e) {
      if (_disposed) return;
      _status = UpdateStatus.error;
      _errorMessage = 'Install failed: $e';
    } finally {
      _installInFlight = false;
      _notify();
    }
  }

  Future<void> _openReleasePage(AppRelease release) async {
    final uri = Uri.tryParse(release.htmlUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw UpdateException('Could not open the release page');
    }
  }

  /// Hides the banner for the current latest version. The persisted write is
  /// best-effort: the UI updates immediately and, at worst, the dismissal is
  /// forgotten on next launch.
  void dismiss() {
    final v = _latestRelease?.version;
    if (v == null || _disposed) return;
    _dismissedVersion = v;
    _notify();
    _persistDismissed(v);
  }

  Future<void> _persistDismissed(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissedKey, version);
    } catch (_) {
      // Best-effort; ignore persistence failures.
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/services/update_service.dart';

/// Counts fetches and returns a scripted release.
class _FakeService extends UpdateService {
  _FakeService(this._release);
  final AppRelease _release;
  int fetchCount = 0;
  @override
  Future<AppRelease> fetchLatestRelease() async {
    fetchCount++;
    return _release;
  }
}

AppRelease _rel(String tag) =>
    AppRelease.fromJson({'tag_name': tag, 'assets': []});

class _PendingService extends UpdateService {
  final result = Completer<AppRelease>();
  final download = Completer<File>();
  int fetches = 0;
  int launches = 0;
  @override
  Future<AppRelease> fetchLatestRelease() {
    fetches++;
    return result.future;
  }

  @override
  String currentOs() => 'macos';
  @override
  String currentArch() => 'arm64';
  @override
  Future<File> downloadAsset(
    ReleaseAsset asset, {
    required void Function(double) onProgress,
  }) => download.future;
  @override
  Future<void> launchInstaller(File file) async {
    launches++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'manual-only default stays offline on startup, focus and timer',
    () async {
      final service = _FakeService(_rel('v0.0.2'));
      final provider = UpdateProvider(service, currentVersion: '0.0.1');
      addTearDown(provider.dispose);
      provider.startPeriodicChecks();
      await provider.checkForUpdates();
      await provider.checkForUpdates();
      expect(service.fetchCount, 0);
      await provider.checkForUpdates(manual: true);
      expect(service.fetchCount, 1);
    },
  );

  test(
    'overlapping manual checks share one request and ignore completion after dispose',
    () async {
      final service = _PendingService();
      final provider = UpdateProvider(service, currentVersion: '0.0.1');
      final first = provider.checkForUpdates(manual: true);
      final second = provider.checkForUpdates(manual: true);
      await Future<void>.delayed(Duration.zero);
      expect(service.fetches, 1);
      provider.dispose();
      service.result.complete(_rel('v0.0.2'));
      await Future.wait([first, second]);
    },
  );

  test(
    'completion after disposal never launches a downloaded update',
    () async {
      final service = _PendingService();
      final provider = UpdateProvider(service, currentVersion: '0.0.1');
      service.result.complete(
        AppRelease.fromJson({
          'tag_name': 'v0.0.2',
          'assets': [
            {'name': 'waytty-0.0.2-macos-universal.zip'},
          ],
        }),
      );
      await provider.checkForUpdates(manual: true);
      final install = provider.downloadAndInstall();
      expect(provider.status, UpdateStatus.downloading);
      provider.dispose();
      service.download.complete(File('unused-fixture.zip'));
      await install;
      expect(service.launches, 0);
    },
  );

  test(
    'a completed download does not permanently disable future checks',
    () async {
      final service = _PendingService();
      final provider = UpdateProvider(service, currentVersion: '0.0.1');
      addTearDown(provider.dispose);
      service.result.complete(
        AppRelease.fromJson({
          'tag_name': 'v0.0.2',
          'assets': [
            {'name': 'waytty-0.0.2-macos-universal.zip'},
          ],
        }),
      );
      await provider.checkForUpdates(manual: true);
      service.download.complete(File('unused-fixture.zip'));
      await provider.downloadAndInstall();
      expect(service.launches, 1);
      expect(provider.status, UpdateStatus.readyToInstall);
      await provider.checkForUpdates(manual: true);
      expect(service.fetches, 2);
    },
  );

  test('manual check finds a newer version -> available', () async {
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18');
    await p.checkForUpdates(manual: true);
    expect(p.status, UpdateStatus.available);
    expect(p.latestRelease!.version, '0.2.0');
    expect(svc.fetchCount, 1);
  });

  test('same version -> upToDate', () async {
    final svc = _FakeService(_rel('v0.1.18'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18');
    await p.checkForUpdates(manual: true);
    expect(p.status, UpdateStatus.upToDate);
  });

  test('auto check is skipped within 24h of the last check', () async {
    final now = DateTime.utc(2026, 6, 3, 12);
    SharedPreferences.setMockInitialValues({
      'last_update_check': now
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch,
    });
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(
      svc,
      currentVersion: '0.1.18',
      automaticChecks: true,
      now: () => now,
    );
    await p.checkForUpdates(); // auto
    expect(svc.fetchCount, 0);
    expect(p.status, UpdateStatus.idle);
  });

  test('auto check runs when >24h since last check', () async {
    final now = DateTime.utc(2026, 6, 3, 12);
    SharedPreferences.setMockInitialValues({
      'last_update_check': now
          .subtract(const Duration(hours: 25))
          .millisecondsSinceEpoch,
    });
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(
      svc,
      currentVersion: '0.1.18',
      automaticChecks: true,
      now: () => now,
    );
    await p.checkForUpdates(); // auto
    expect(svc.fetchCount, 1);
    expect(p.status, UpdateStatus.available);
  });

  test('dismiss hides the banner for that version only', () async {
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18');
    await p.checkForUpdates(manual: true);
    expect(p.showBanner, isTrue);
    p.dismiss();
    expect(p.showBanner, isFalse);
  });

  group('periodic checks', () {
    test('timer fires an auto check and stays debounced within 24h', () {
      fakeAsync((async) {
        var clock = DateTime.utc(2026, 6, 3, 12);
        final svc = _FakeService(_rel('v0.2.0'));
        final p = UpdateProvider(
          svc,
          currentVersion: '0.1.18',
          automaticChecks: true,
          now: () => clock,
          checkInterval: const Duration(hours: 6),
        );
        p.startPeriodicChecks();

        // First tick: no prior check recorded -> fetches.
        async.elapse(const Duration(hours: 6));
        expect(svc.fetchCount, 1);

        // Two more ticks inside the 24h debounce window -> no fetch.
        async.elapse(const Duration(hours: 12));
        expect(svc.fetchCount, 1);

        // Move the injected clock past the debounce window; next tick fetches.
        clock = clock.add(const Duration(hours: 25));
        async.elapse(const Duration(hours: 6));
        expect(svc.fetchCount, 2);

        p.dispose();
      });
    });

    test('startPeriodicChecks is idempotent (replaces the old timer)', () {
      fakeAsync((async) {
        final svc = _FakeService(_rel('v0.2.0'));
        final p = UpdateProvider(
          svc,
          currentVersion: '0.1.18',
          automaticChecks: true,
          checkInterval: const Duration(hours: 6),
        );
        p.startPeriodicChecks();
        p.startPeriodicChecks();
        expect(async.pendingTimers.length, 1);
        p.dispose();
      });
    });

    test('dispose cancels the timer', () {
      fakeAsync((async) {
        final svc = _FakeService(_rel('v0.2.0'));
        final p = UpdateProvider(
          svc,
          currentVersion: '0.1.18',
          automaticChecks: true,
          checkInterval: const Duration(hours: 6),
        );
        p.startPeriodicChecks();
        p.dispose();
        async.elapse(const Duration(hours: 12));
        expect(svc.fetchCount, 0);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}

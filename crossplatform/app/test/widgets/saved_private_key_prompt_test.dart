import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/saved_private_key_controls.dart';
import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_connection_attempt.dart';
import 'package:yourssh/models/ssh_credentials.dart';
import 'package:yourssh/services/local_ssh_key_store.dart';
import 'package:yourssh/widgets/ssh_credentials_dialog.dart';
import 'package:yourssh/widgets/ssh_key_unlock_dialog.dart';

class FakeSsh extends SshService {
  final FakeKeys keys;
  FakeSsh(this.keys) : super(StorageService());
  @override
  LocalSshKeyStore get savedPrivateKeys => keys;
}

class FakeKeys extends LocalSshKeyStore {
  SshCredentials? saved;
  bool isOpen = false;
  bool setup = false;
  int saves = 0;
  Completer<void>? unlockGate;
  int generation = 0;
  @override
  Future<void> load() async {}
  @override
  Future<void> remove(String id) async {
    saved = null;
    lock();
    notifyListeners();
  }

  @override
  bool get configured => setup;
  @override
  bool get unlocked => isOpen;
  @override
  bool hasKey(String id) => saved != null;
  @override
  Future<SshCredentials?> read(Host host) async => saved;
  @override
  Future<void> unlock(String password) async {
    final started = generation;
    await unlockGate?.future;
    if (started != generation) throw const AuthenticationCancelled();
    if (password != 'fixture-password') throw const FormatException();
    setup = true;
    isOpen = true;
    notifyListeners();
  }

  @override
  void lock() {
    generation++;
    isOpen = false;
    notifyListeners();
  }

  @override
  Future<void> save(
    Host host,
    SshCredentials input, {
    bool Function()? cancelled,
  }) async {
    if (cancelled?.call() == true) throw const AuthenticationCancelled();
    saved = input;
    saves++;
    notifyListeners();
  }
}

void main() {
  final host = Host(
    id: 'fixture',
    label: 'fixture',
    host: 'fixture.invalid',
    username: 'fixture',
    authType: AuthType.privateKey,
  );
  final pem = File('test/fixtures/keys/id_ed25519_enc').readAsStringSync();
  late ManualCredentialPrompts prompts;
  late FakeKeys store;
  Future<void> mount(
    WidgetTester tester, {
    bool canSave = true,
    String locale = 'en',
  }) async {
    store = FakeKeys();
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        supportedLocales: WayttyStrings.supportedLocales,
        localizationsDelegates: WayttyStrings.delegates,
        home: Builder(
          builder: (context) {
            prompts = ManualCredentialPrompts(
              () => context,
              privateKeys: store,
              canSaveKey: (_) async => canSave,
            );
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );
  }

  Future<void> paste(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, pem);
    await tester.enterText(find.byType(TextField).last, 'test-passphrase');
  }

  testWidgets('save with connection then reuse without prompting again', (
    tester,
  ) async {
    await mount(tester);
    final request = prompts.request(host);
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await paste(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.byType(SshKeyUnlockDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'fixture-password');
    await tester.enterText(find.byType(TextField).last, 'fixture-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect((await request)!.privateKey, pem);
    expect(store.saves, 1);
    expect((await prompts.request(host))!.privateKey, pem);
    expect(find.byType(SshCredentialsDialog), findsNothing);
  });

  testWidgets('opt out and unsaved test connection never persist a key', (
    tester,
  ) async {
    for (final canSave in [true, false]) {
      await mount(tester, canSave: canSave);
      final request = prompts.request(host);
      await tester.pumpAndSettle();
      await paste(tester);
      if (canSave) await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      expect((await request)!.privateKey, pem);
      expect(store.saves, 0);
      expect(store.isOpen, isFalse);
      expect(find.byType(SshKeyUnlockDialog), findsNothing);
    }
  });

  testWidgets('restart prompts only for unlock; wrong password stays locked', (
    tester,
  ) async {
    await mount(tester);
    store.saved = SshCredentials(privateKey: pem);
    store.setup = true;
    final request = prompts.request(host);
    await tester.pumpAndSettle();
    expect(find.byType(SshCredentialsDialog), findsNothing);
    await tester.enterText(find.byType(TextField), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(store.isOpen, isFalse);
    expect(
      find.text(
        'Could not unlock saved keys. Check the password and try again.',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'fixture-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect((await request)!.privateKey, pem);
    expect(store.saves, 0);
  });

  testWidgets('cancel during unlock prevents later unlock or connection', (
    tester,
  ) async {
    await mount(tester);
    store.saved = SshCredentials(privateKey: pem);
    store.setup = true;
    store.unlockGate = Completer();
    final attempt = SshConnectionAttempt();
    final request = prompts.request(host, attempt);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fixture-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pump();
    attempt.cancel();
    await tester.pumpAndSettle();
    store.unlockGate!.complete();
    await tester.pumpAndSettle();
    expect(await request, isNull);
    expect(store.isOpen, isFalse);
    expect(store.saves, 0);
  });

  testWidgets(
    'replace and delete controls use explicit actions without showing the saved key',
    (tester) async {
      final keys = FakeKeys()
        ..saved = SshCredentials(privateKey: pem)
        ..setup = true;
      final ssh = FakeSsh(keys);
      int edits = 0;
      ssh.privateKeyEditor = (h) async {
        expect(h.id, host.id);
        edits++;
      };
      await tester.pumpWidget(
        Provider<SshService>.value(
          value: ssh,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: WayttyStrings.supportedLocales,
            localizationsDelegates: WayttyStrings.delegates,
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: SavedPrivateKeyControls(host: host),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(pem), findsNothing);
      await tester.tap(
        find.widgetWithText(TextButton, 'Replace saved private key'),
      );
      await tester.pumpAndSettle();
      expect(edits, 1);
      await tester.tap(
        find.widgetWithText(TextButton, 'Delete saved private key'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(keys.saved, isNotNull);
      await tester.tap(
        find.widgetWithText(TextButton, 'Delete saved private key'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(keys.saved, isNull);
      expect(
        find.text('No private key saved for this connection'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Chinese dialog fits narrow screen and invalid key stays in dialog',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, locale: 'zh');
      final request = prompts.request(host);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'fixture-not-a-key');
      await tester.tap(find.widgetWithText(FilledButton, '连接'));
      await tester.pumpAndSettle();
      expect(find.text('私钥、证书或私钥口令无效。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(await request, isNull);
    },
  );
}

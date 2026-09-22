import 'dart:typed_data';
import '../helpers/secure_store.dart';
import 'package:yourssh/models/ssh_connection_attempt.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/mobile_bootstrap.dart';
import 'package:yourssh/providers/port_forward_provider.dart';
import 'package:yourssh/services/key_gen_service.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

void main() {
  setUp(installSecureStoreMock);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('constructs services and wires cancellable trust verification', () async {
    final b = MobileBootstrap();

    // Connect-critical callbacks must be wired.
    expect(b.sessions.keyLookup, isNotNull);
    expect(b.sessions.autoReconnectEnabled, isNotNull);
    expect(b.sessions.terminalType, isNotNull);
    expect(b.ssh.defaultHostKeyVerifier, isNotNull);
    expect(b.ssh.defaultKeyLookup, isNotNull);

    // Exposes a provider list for the widget tree.
    expect(b.providers, isNotEmpty);
    final attempt = SshConnectionAttempt();
    final decision = b.ssh.defaultHostKeyVerifier!(
      'fixture.invalid', 22, 'ssh-ed25519', Uint8List(16), attempt: attempt);
    expect(b.knownHosts.pendingChallenge, isNotNull);
    attempt.cancel();
    expect(await decision, false);
    expect(b.knownHosts.hosts, isEmpty);
    // Let constructor-started fixture loads finish before tearing services down.
    await Future<void>.delayed(Duration.zero);
    b.dispose();
  });

  test('exposes local/cloud mode provider', () {
    final b = MobileBootstrap();
    expect(b.sync, isNotNull);
  });

  test('exposes snippets + transfer service', () {
    final b = MobileBootstrap();
    expect(b.snippets, isNotNull);
    expect(b.transfer, isNotNull);
  });

  test('exposes port-forward provider + service', () {
    final b = MobileBootstrap();
    expect(b.portForwardProvider, isNotNull);
    expect(b.portForwardService, isNotNull);
  });

  testWidgets('providers resolve from a child context', (tester) async {
    final b = MobileBootstrap();
    late BuildContext childCtx;
    await tester.pumpWidget(MultiProvider(
      providers: b.providers,
      child: Builder(builder: (ctx) {
        childCtx = ctx;
        return const SizedBox();
      }),
    ));

    // These assertions exercise the real Flutter Provider lookup path — a wrong
    // type param or Provider.value vs ChangeNotifierProvider.value mismatch
    // would throw here even though field-access checks above would pass.
    expect(Provider.of<PortForwardProvider>(childCtx, listen: false), isNotNull);
    expect(Provider.of<SnippetProvider>(childCtx, listen: false), isNotNull);
    // Regression: KeyGenService was missing from the provider list prior to
    // the fix; opening the Generate sheet would throw ProviderNotFoundException.
    expect(Provider.of<KeyGenService>(childCtx, listen: false), isNotNull);
  });
}

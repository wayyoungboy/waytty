import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/share_provider.dart';

void main() {
  test('sharing is unavailable without a self-hosted transport', () async {
    final share = ShareProvider();
    addTearDown(share.dispose);
    expect(share.canShare, false);
    expect(share.isSharing, false);
    expect(share.isGuest, false);
    await expectLater(share.startSharing('session'), throwsStateError);
    await expectLater(share.joinSession('ABC123'), throwsStateError);
    expect(share.isSharing, false);
    expect(share.isGuest, false);
  });
}

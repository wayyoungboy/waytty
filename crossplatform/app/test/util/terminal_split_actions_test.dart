import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/terminal_split_actions.dart';

void main() {
  test('soft cap is 15 (XTerminal WebGL guidance)', () {
    expect(kMaxTerminalSessions, 15);
  });
}

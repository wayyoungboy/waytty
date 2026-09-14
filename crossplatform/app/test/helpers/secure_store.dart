import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory platform keychain, never SharedPreferences or the real OS store.
void installSecureStoreMock() {
  final values = <String, String>{};
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final key = args['key'] as String?;
      switch (call.method) {
        case 'write': values[key!] = args['value'] as String; return null;
        case 'read': return values[key];
        case 'delete': values.remove(key); return null;
        case 'containsKey': return values.containsKey(key);
        case 'readAll': return Map.of(values);
        case 'deleteAll': values.clear(); return null;
      }
      return null;
    });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/settings.dart';
import 'package:neurolens/core/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a saved localhost address from an earlier version is replaced by the built-in server', () async {
    SharedPreferences.setMockInitialValues({'baseUrl': 'http://localhost:8000'});
    final s = AppSettings(await SharedPreferences.getInstance(), tokens: MemoryTokenStore(null));
    expect(s.baseUrl, AppSettings.defaultServer);
    expect(s.isCustomServer, isFalse);
  });

  test('a real custom server is kept', () async {
    SharedPreferences.setMockInitialValues({'baseUrl': 'http://192.168.1.5:8000'});
    final s = AppSettings(await SharedPreferences.getInstance(), tokens: MemoryTokenStore(null));
    expect(s.baseUrl, 'http://192.168.1.5:8000');
  });
}

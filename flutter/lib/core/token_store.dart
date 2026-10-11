import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the sign-in session lives. On a phone this is the system keystore (Android Keystore / iOS Keychain), not plain app storage.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _key = 'session_token';
  static const _s = FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      return await _s.read(key: _key);
    } catch (_) {
      return null; // a keystore that can't be read (for example after a restore) just means "signed out"
    }
  }

  @override
  Future<void> write(String token) => _s.write(key: _key, value: token);

  @override
  Future<void> clear() async {
    try {
      await _s.delete(key: _key);
    } catch (_) {}
  }
}

/// For tests.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._token]);
  String? _token;

  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String token) async => _token = token;
  @override
  Future<void> clear() async => _token = null;
}

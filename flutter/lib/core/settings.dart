import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'token_store.dart';

/// Where the NeuroLens server is, the signed-in session, and display preferences.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs, {TokenStore? tokens, String? sessionToken})
      : _tokens = tokens ?? const SecureTokenStore(),
        _session = sessionToken,
        _baseUrl = _savedServer(_prefs),
        _theme = ThemeMode.values[(_prefs.getInt('theme') ?? 0).clamp(0, 2)];

  /// Where the NeuroLens server is, built in so nobody has to type it. Settings can override it (for example a server on your Wi-Fi).
  static const defaultServer = 'https://neurolens.moveneticsdigital.com';

  /// An address saved by an earlier version. "localhost" on a phone means the phone itself, where no server runs, so such a
  /// value (left over from testing over a cable) is dropped and the built-in server is used instead.
  static String _savedServer(SharedPreferences prefs) {
    final v = prefs.getString('baseUrl') ?? '';
    if (RegExp(r'^https?://(localhost|127\.|0\.0\.0\.0|\[::1\])', caseSensitive: false).hasMatch(v)) {
      prefs.remove('baseUrl');
      return '';
    }
    return v;
  }

  final SharedPreferences _prefs;
  final TokenStore _tokens;
  String _baseUrl;
  String? _session;
  ThemeMode _theme;

  static Future<AppSettings> load({TokenStore? tokens}) async {
    final store = tokens ?? const SecureTokenStore();
    return AppSettings(await SharedPreferences.getInstance(), tokens: store, sessionToken: await store.read());
  }

  String get baseUrl => _baseUrl.isEmpty ? defaultServer : _baseUrl;
  bool get isCustomServer => _baseUrl.isNotEmpty;
  bool get hasServer => true;
  bool get introSeen => _prefs.getBool('introSeen') ?? false;
  ThemeMode get themeMode => _theme;
  SharedPreferences get prefs => _prefs;

  /// The sign-in session this phone holds, if any.
  String? get sessionToken => _session;
  bool get isSignedIn => _session != null && _session!.isNotEmpty;

  /// Accepts "192.168.1.5:8000", "my-site.ngrok-free.dev" or a full URL, and stores it without a trailing slash.
  static String normalizeUrl(String input) {
    var u = input.trim();
    if (u.isEmpty) return '';
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(u)) {
      final local = RegExp(r'^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)').hasMatch(u);
      u = '${local ? 'http' : 'https'}://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = normalizeUrl(url);
    if (_baseUrl == defaultServer) _baseUrl = '';
    await (_baseUrl.isEmpty ? _prefs.remove('baseUrl') : _prefs.setString('baseUrl', _baseUrl));
    notifyListeners();
  }

  Future<void> useDefaultServer() async {
    _baseUrl = '';
    await _prefs.remove('baseUrl');
    notifyListeners();
  }

  Future<void> setIntroSeen() async {
    await _prefs.setBool('introSeen', true);
    notifyListeners();
  }

  Future<void> setSession(String? token) async {
    _session = token;
    if (token == null) {
      await _tokens.clear();
    } else {
      await _tokens.write(token);
    }
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    _theme = m;
    await _prefs.setInt('theme', m.index);
    notifyListeners();
  }
}

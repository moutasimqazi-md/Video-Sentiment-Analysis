import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'account_models.dart';
import 'api.dart';
import 'settings.dart';
import 'imports/import_store.dart';
import 'stores.dart';

enum AuthStatus { starting, signedOut, signedIn }

/// Who is signed in, their plan and usage. Owns sign up, sign in, sign out, subscription changes and account deletion, and
/// points the on-phone history and child profiles at the right account.
class AuthController extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  AuthController(this._api, this._settings, this._history, this._profiles, this._jobs, {ImportStore? imports}) : _imports = imports {
    _api.onSessionExpired = _expired;
  }
  final ApiClient _api;
  final AppSettings _settings;
  final HistoryStore _history;
  final ProfilesStore _profiles;
  final JobQueue _jobs;
  final ImportStore? _imports;

  AuthStatus status = AuthStatus.starting;
  Me? me;
  List<Plan> plans = const [];
  bool paymentsDemo = true; // the server says whether choosing a plan really charges anyone
  String? notice; // shown on the sign-in screen, e.g. "Please sign in again."
  bool offline = false; // signed in, but the server could not be reached on launch

  bool get signedIn => status == AuthStatus.signedIn;

  static const _cacheKey = 'me_cache';

  void _apply(Me m) {
    me = m;
    _history.limit = m.plan.history;
    _history.switchUser(m.userId);
    _profiles.switchUser(m.userId);
    _imports?.switchUser(m.userId);
    _settings.prefs.setString(_cacheKey, jsonEncode(m.toJson()));
  }

  /// On launch: check the saved session with the server. A bad session signs out; no connection keeps the saved account so the
  /// app still opens (history and saved results work offline).
  Future<void> restore() async {
    await Future<void>.delayed(Duration.zero); // never notify listeners while a screen is still being built
    if (!_settings.isSignedIn) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    try {
      _apply(await _api.me());
      offline = false;
      status = AuthStatus.signedIn;
    } on ApiException catch (e) {
      if (e.unauthorized) {
        await _clearLocal(notice: 'Please sign in again.');
        return;
      }
      _useCache();
    }
    notifyListeners();
  }

  void _useCache() {
    try {
      final raw = _settings.prefs.getString(_cacheKey);
      if (raw != null) {
        _apply(Me.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>()));
        offline = true;
        status = AuthStatus.signedIn;
        return;
      }
    } catch (_) {}
    status = AuthStatus.signedOut;
  }

  Future<void> signup({required String name, required String email, required String password}) async {
    final r = await _api.signup(name: name.trim(), email: email.trim(), password: password, device: _device());
    await _signedIn(r.token, r.me);
  }

  Future<void> login({required String email, required String password}) async {
    final r = await _api.login(email: email.trim(), password: password, device: _device());
    await _signedIn(r.token, r.me);
  }

  String _device() => switch (defaultTargetPlatform) { TargetPlatform.android => 'Android phone', TargetPlatform.iOS => 'iPhone', _ => 'Web browser' };

  Future<void> _signedIn(String token, Me m) async {
    await _settings.setSession(token);
    _apply(m);
    notice = null;
    offline = false;
    status = AuthStatus.signedIn;
    notifyListeners();
    loadPlans();
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } catch (_) {} // the local sign-out happens regardless
    await _clearLocal();
  }

  void _expired() {
    if (status == AuthStatus.signedIn) _clearLocal(notice: 'You were signed out. Please sign in again.');
  }

  Future<void> _clearLocal({String? notice}) async {
    await _settings.setSession(null);
    await _settings.prefs.remove(_cacheKey);
    _history.switchUser(null);
    _profiles.switchUser(null);
    _imports?.switchUser(null);
    _jobs.reset();
    me = null;
    this.notice = notice;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!signedIn) return;
    try {
      _apply(await _api.me());
      offline = false;
      notifyListeners();
    } on ApiException catch (_) {}
  }

  Future<void> loadPlans() async {
    try {
      final r = await _api.plans();
      plans = r.plans;
      paymentsDemo = r.demo;
      notifyListeners();
    } on ApiException catch (_) {}
  }

  /// Switch plan. Returns the server's message (in demo mode it says no charge was made).
  Future<String?> subscribe(String planId, String cycle) async {
    final r = await _api.subscribe(planId, cycle);
    _apply(r.me);
    notifyListeners();
    return r.message;
  }

  Future<void> cancelPlan() async {
    _apply(await _api.cancelPlan());
    notifyListeners();
  }

  Future<void> rename(String name) async {
    _apply(await _api.updateName(name));
    notifyListeners();
  }

  Future<void> changePassword(String current, String next) => _api.changePassword(current, next);

  /// Permanently deletes the account on the server and this account's data on the phone.
  Future<void> deleteAccount(String password) async {
    final uid = me?.userId;
    await _api.deleteAccount(password);
    if (uid != null) {
      await _history.wipe(uid);
      await _profiles.wipe(uid);
      await _imports?.wipe(uid);
    }
    await _clearLocal(notice: 'Your account was deleted.');
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'settings.dart';

/// The alerts raised by Feed checks (owner tools). Polls while the app is open and this phone is paired.
class AlertsController extends ChangeNotifier {
  AlertsController(this._api, this._settings) {
    _settings.addListener(_sync);
    _sync();
  }
  final ApiClient _api;
  final AppSettings _settings;
  Timer? _timer;
  List<AlertItem> _alerts = const [];
  int _unread = 0;
  String? error;
  bool loading = false;

  List<AlertItem> get alerts => _alerts;
  int get unread => _unread;

  void _sync() {
    if (_settings.isSignedIn) {
      _timer ??= Timer.periodic(const Duration(seconds: 45), (_) => refresh());
      refresh();
    } else {
      _timer?.cancel();
      _timer = null;
      _alerts = const [];
      _unread = 0;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!_settings.isSignedIn) return;
    loading = true;
    try {
      final r = await _api.alerts(limit: 50);
      _alerts = r.alerts;
      _unread = r.unread;
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(List<String> ids) async {
    try {
      await _api.markAlertsRead(ids);
    } catch (_) {}
    await refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _settings.removeListener(_sync);
    super.dispose();
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'habits.dart';

/// Saved habits reports from imported Instagram / YouTube / TikTok / Facebook history, kept on this phone for the signed-in account only.
/// One report per profile and platform (never combined). The export files themselves are never stored.
class ImportStore extends ChangeNotifier {
  ImportStore(this._prefs, {String? userId}) : _uid = userId;
  final SharedPreferences _prefs;
  String? _uid;

  static const platforms = ['ig', 'yt', 'tt', 'fb'];
  static const platformNames = {'ig': 'Instagram', 'yt': 'YouTube', 'tt': 'TikTok', 'fb': 'Facebook'};

  String _key(String profile, String src) => 'imp_${_uid ?? 'none'}_${profile}_$src';
  String get _indexKey => 'imp_index_${_uid ?? 'none'}';

  void switchUser(String? userId) {
    _uid = userId;
    notifyListeners();
  }

  List<(String, String)> _index() {
    if (_uid == null) return [];
    final out = <(String, String)>[];
    for (final k in _prefs.getStringList(_indexKey) ?? const <String>[]) {
      final i = k.lastIndexOf('|');
      if (i > 0) out.add((k.substring(0, i), k.substring(i + 1)));
    }
    return out;
  }

  Json? get(String profile, String src) {
    if (_uid == null) return null;
    try {
      final raw = _prefs.getString(_key(profile, src));
      return raw == null ? null : (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Every saved report as (profile id, platform, report).
  List<(String, String, Json)> all() => [for (final (p, s) in _index()) if (get(p, s) case final r?) (p, s, r)];

  List<String> sourcesFor(String profile) => [for (final s in platforms) if (get(profile, s) != null) s];

  Future<void> save(String profile, String src, Json report) async {
    if (_uid == null) return;
    final prev = get(profile, src);
    if (prev != null && prev['platforms'] != null) report['prev'] = snapshotOf(prev);
    await _prefs.setString(_key(profile, src), jsonEncode(report));
    final idx = (_prefs.getStringList(_indexKey) ?? <String>[]).toSet()..add('$profile|$src');
    await _prefs.setStringList(_indexKey, idx.toList());
    notifyListeners();
  }

  Future<void> remove(String profile, String src) async {
    if (_uid == null) return;
    await _prefs.remove(_key(profile, src));
    await _prefs.setStringList(_indexKey, (_prefs.getStringList(_indexKey) ?? <String>[]).where((k) => k != '$profile|$src').toList());
    notifyListeners();
  }

  /// Removes everything saved for an account (on account deletion).
  Future<void> wipe(String userId) async {
    final idx = _prefs.getStringList('imp_index_$userId') ?? const <String>[];
    for (final k in idx) {
      final i = k.lastIndexOf('|');
      if (i > 0) await _prefs.remove('imp_${userId}_${k.substring(0, i)}_${k.substring(i + 1)}');
    }
    await _prefs.remove('imp_index_$userId');
    if (_uid == userId) _uid = null;
    notifyListeners();
  }
}

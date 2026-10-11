import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

/// Saved analyses, kept on this phone, separately for each signed-in account (two people sharing a phone never see each other's).
class HistoryStore extends ChangeNotifier {
  HistoryStore(this._prefs, {String? userId}) {
    switchUser(userId, notify: false);
  }
  final SharedPreferences _prefs;
  final List<HistoryEntry> _items = [];
  String? _uid;
  int limit = maxItems; // the plan decides how many analyses are kept
  static const maxItems = 1000;

  String get _key => 'history_${_uid ?? 'none'}';

  /// Load another account's history (or none, when signed out).
  void switchUser(String? userId, {bool notify = true}) {
    _uid = userId;
    _items.clear();
    if (userId != null) {
      try {
        final raw = _prefs.getString(_key);
        if (raw != null) _items.addAll((jsonDecode(raw) as List).whereType<Map>().map((m) => HistoryEntry.fromJson(m.cast<String, dynamic>())));
      } catch (_) {
        _items.clear(); // a corrupt save is dropped rather than crashing the app
      }
    }
    if (notify) notifyListeners();
  }

  List<HistoryEntry> get items => List.unmodifiable(_items);
  HistoryEntry? byId(String id) => _items.where((e) => e.id == id).firstOrNull;
  List<HistoryEntry> forProfile(String profileId) => _items.where((e) => e.profileId == profileId).toList();

  Future<void> add(HistoryEntry e) async {
    _items.removeWhere((x) => x.id == e.id);
    _items.insert(0, e);
    if (_items.length > limit) _items.removeRange(limit, _items.length);
    await _save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    await _save();
  }

  Future<void> setFeedback(String id, String rating) async {
    byId(id)?.feedback = rating;
    await _save();
  }

  Future<void> removeProfile(String profileId) async {
    _items.removeWhere((e) => e.profileId == profileId);
    await _save();
  }

  Future<void> clear() async {
    _items.clear();
    await _save();
  }

  /// Delete this account's saved history from the phone (used when the account is deleted).
  Future<void> wipe(String userId) async {
    await _prefs.remove('history_$userId');
    if (_uid == userId) switchUser(null);
  }

  Future<void> _save() async {
    notifyListeners();
    if (_uid != null) await _prefs.setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));
  }
}

/// Child profiles, kept on the phone per account.
class ProfilesStore extends ChangeNotifier {
  ProfilesStore(this._prefs, {String? userId}) {
    switchUser(userId, notify: false);
  }
  final SharedPreferences _prefs;
  final List<ChildProfile> _children = [];
  String _active = 'me';
  String? _uid;

  String get _ck => 'children_${_uid ?? 'none'}';
  String get _ak => 'activeProfile_${_uid ?? 'none'}';

  void switchUser(String? userId, {bool notify = true}) {
    _uid = userId;
    _children.clear();
    _active = 'me';
    if (userId != null) {
      try {
        final raw = _prefs.getString(_ck);
        if (raw != null) _children.addAll((jsonDecode(raw) as List).whereType<Map>().map((m) => ChildProfile.fromJson(m.cast<String, dynamic>())));
      } catch (_) {
        _children.clear();
      }
      _active = _prefs.getString(_ak) ?? 'me';
      if (_active != 'me' && !_children.any((c) => c.id == _active)) _active = 'me';
    }
    if (notify) notifyListeners();
  }

  List<ChildProfile> get children => List.unmodifiable(_children);
  String get active => _active;
  ChildProfile? get(String id) => _children.where((c) => c.id == id).firstOrNull;
  String nameOf(String id) => id == 'me' ? 'Me' : (get(id)?.name ?? 'Unknown');

  /// The server only accepts ids of lowercase letters, digits, `_` and `-`.
  Future<ChildProfile> add(String name, int? age) async {
    final c = ChildProfile(id: 'c${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}', name: name.trim(), age: age);
    _children.add(c);
    await _save();
    return c;
  }

  Future<void> remove(String id) async {
    _children.removeWhere((c) => c.id == id);
    if (_active == id) _active = 'me';
    await _save();
  }

  Future<void> setActive(String id) async {
    _active = id;
    if (_uid != null) await _prefs.setString(_ak, id);
    notifyListeners();
  }

  Future<void> wipe(String userId) async {
    await _prefs.remove('children_$userId');
    await _prefs.remove('activeProfile_$userId');
    if (_uid == userId) switchUser(null);
  }

  Future<void> _save() async {
    notifyListeners();
    if (_uid == null) return;
    await _prefs.setString(_ck, jsonEncode(_children.map((c) => c.toJson()).toList()));
    await _prefs.setString(_ak, _active);
  }
}

/// Runs analyses in the background: uploads or sends links, polls the server, and saves each result to History.
class JobQueue extends ChangeNotifier {
  JobQueue(this._api, this._history);
  final ApiClient _api;
  final HistoryStore _history;
  final List<Job> _jobs = [];
  Timer? _timer;
  final _doneController = StreamController<Job>.broadcast();

  /// Fires once for each job that finishes, so screens can show a "ready" message.
  Stream<Job> get onDone => _doneController.stream;
  List<Job> get jobs => List.unmodifiable(_jobs);
  List<Job> get active => _jobs.where((j) => j.active).toList();

  void _touch() => notifyListeners();

  Future<Job> addLink(String url, {required String profileId, String? title}) async {
    final job = Job(localId: _id(), title: title ?? url, profileId: profileId, url: url)..stage = 'Sending';
    _jobs.insert(0, job);
    _touch();
    try {
      job.serverId = await _api.analyzeLink(url);
      _poll();
    } catch (e) {
      _fail(job, e.toString());
    }
    return job;
  }

  /// [open] is called when the upload starts, so a file can be streamed from disk instead of being read into memory.
  Future<Job> addFile(Stream<List<int>> Function() open, int length, String filename, {required String profileId, String? mime}) async {
    final isImage = (mime ?? '').startsWith('image/') || RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(filename);
    final job = Job(localId: _id(), title: filename, profileId: profileId, isImage: isImage)
      ..state = JobState.uploading
      ..stage = 'Uploading';
    _jobs.insert(0, job);
    _touch();
    try {
      job.serverId = await _api.uploadStream(open, length, filename, mime: mime);
      job.state = JobState.queued;
      job.stage = 'Queued';
      _touch();
      _poll();
    } catch (e) {
      _fail(job, e.toString());
    }
    return job;
  }

  /// Forget everything in progress (when someone signs out).
  void reset() {
    _timer?.cancel();
    _timer = null;
    _jobs.clear();
    _touch();
  }

  void dismiss(Job j) {
    _jobs.remove(j);
    _touch();
  }

  void clearFinished() {
    _jobs.removeWhere((j) => !j.active);
    _touch();
  }

  Future<Job> retry(Job j) async {
    dismiss(j);
    if (j.url != null) return addLink(j.url!, profileId: j.profileId, title: j.title);
    throw ApiException('Choose the file again to retry.');
  }

  String _id() => 'j${DateTime.now().microsecondsSinceEpoch}';

  void _fail(Job j, String message) {
    j.state = JobState.error;
    j.error = message;
    j.stage = 'Failed';
    _touch();
  }

  void _poll() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 1500), (_) => _tick());
  }

  bool _ticking = false;
  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final pending = _jobs.where((j) => j.active && j.serverId != null).toList();
      if (pending.isEmpty && _jobs.every((j) => !j.active)) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      for (final j in pending) {
        try {
          final s = await _api.jobStatus(j.serverId!);
          if (s.status == 'done' && s.result != null) {
            await _finish(j, s.result!);
          } else if (s.status == 'error') {
            _fail(j, s.error ?? 'Analysis failed');
          } else {
            j.state = s.status == 'running' ? JobState.running : JobState.queued;
            j.stage = s.stage.isEmpty ? 'Working' : s.stage;
            if (s.progress > j.progress) j.progress = s.progress;
            _touch();
          }
        } on ApiException catch (e) {
          if (e.status == 404) _fail(j, 'This analysis expired before it finished. Please run it again.');
          // anything else (a network blip): try again on the next tick
        }
      }
    } finally {
      _ticking = false;
    }
  }

  Future<void> _finish(Job j, Map<String, dynamic> result) async {
    final title = (j.title == j.url ? null : j.title) ?? (result['source'] as Map?)?['title'] as String? ?? j.title;
    final entry = HistoryEntry(
      id: j.serverId!,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      title: title,
      profileId: j.profileId,
      result: result,
      sourceUrl: j.url,
    );
    await _history.add(entry);
    j
      ..state = JobState.done
      ..stage = 'Ready'
      ..progress = 1
      ..entryId = entry.id
      ..title = title;
    _touch();
    _doneController.add(j);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _doneController.close();
    super.dispose();
  }
}

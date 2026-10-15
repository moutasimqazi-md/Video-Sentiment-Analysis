import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'account_models.dart';
import 'models.dart';
import 'settings.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  bool get unauthorized => status == 401;
  bool get planLimit => status == 402; // out of analyses, or the plan does not include this
  @override
  String toString() => message;
}

class JobStatus {
  JobStatus({required this.status, required this.stage, required this.progress, this.result, this.error});
  final String status, stage;
  final double progress;
  final Map<String, dynamic>? result;
  final String? error;
}

/// Talks to the NeuroLens backend (FastAPI). Every call carries the signed-in session, so the server can count usage against the
/// plan and keep each person's Feed checks, children and alerts apart from everyone else's.
class ApiClient {
  ApiClient(this.settings, {http.Client? client}) : _http = client ?? http.Client();
  final AppSettings settings;
  final http.Client _http;

  /// Called when the server says the session is no longer valid (signed out elsewhere, password changed, account deleted).
  void Function()? onSessionExpired;

  static const _skipNgrokWarning = {'ngrok-skip-browser-warning': '1'};

  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(settings.baseUrl);
    final clean = path.startsWith('/') ? path.substring(1) : path;
    final qIndex = clean.indexOf('?');
    final p = qIndex >= 0 ? clean.substring(0, qIndex) : clean;
    final q = <String, String>{...?(qIndex >= 0 ? Uri.splitQueryString(clean.substring(qIndex + 1)) : null), ...?query};
    return base.replace(path: '${base.path.endsWith('/') ? base.path : '${base.path}/'}$p', queryParameters: q.isEmpty ? null : q);
  }

  /// Absolute URL for a server-relative path such as a key-moment image.
  String absolute(String path) => path.startsWith('http') ? path : uri(path).toString();
  String thumbnailUrl(String jobId) => uri('api/thumbnails/$jobId.jpg').toString();

  Map<String, String> _headers({bool json = false}) => {
        ..._skipNgrokWarning,
        if (json) 'Content-Type': 'application/json',
        if (settings.isSignedIn) 'X-User-Token': settings.sessionToken!,
      };

  Never _fail(Object e) {
    if (e is ApiException) throw e;
    if (e is TimeoutException) throw ApiException('The server took too long to answer. Try again.');
    throw ApiException("Can't reach the NeuroLens server. Check the address in Settings and your connection.");
  }

  dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      var msg = 'Request failed (${r.statusCode})';
      if (body is Map && body['detail'] is String) msg = body['detail'] as String;
      if (r.statusCode == 401 && settings.isSignedIn && msg.startsWith('Please sign in')) onSessionExpired?.call();
      throw ApiException(msg, status: r.statusCode);
    }
    return body;
  }

  Future<dynamic> _send(String method, String path, {Object? body, Duration timeout = const Duration(seconds: 25)}) async {
    try {
      final req = http.Request(method, uri(path))..headers.addAll(_headers(json: body != null));
      if (body != null) req.body = jsonEncode(body);
      final res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
      return _decode(res);
    } catch (e) {
      _fail(e);
    }
  }

  // ---------------- public analysis routes ----------------
  Future<bool> ping() async {
    try {
      await _send('GET', 'api/model/info', timeout: const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Checks a server address before it is saved.
  Future<bool> probe(String baseUrl) async {
    try {
      final res = await _http.get(Uri.parse('$baseUrl/api/model/info'), headers: _headers()).timeout(const Duration(seconds: 8));
      return res.statusCode == 200 && (jsonDecode(res.body) as Map).containsKey('learning');
    } catch (_) {
      return false;
    }
  }

  Future<String> analyzeLink(String url) async => (await _send('POST', 'api/analyze-link', body: {'url': url}))['job_id'] as String;

  /// Streams a video or image to the server, so a large file is never held in memory all at once.
  Future<String> uploadStream(Stream<List<int>> Function() open, int length, String filename, {String? mime}) async {
    try {
      final req = http.MultipartRequest('POST', uri('api/analyze'))..headers.addAll(_headers());
      MediaType? type;
      if (mime != null && mime.contains('/')) type = MediaType.parse(mime);
      req.files.add(http.MultipartFile('file', open(), length, filename: filename, contentType: type));
      final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 10)));
      return (_decode(res) as Map)['job_id'] as String;
    } catch (e) {
      _fail(e);
    }
  }

  Future<String> uploadFile(Uint8List bytes, String filename, {String? mime}) => uploadStream(() => Stream.value(bytes), bytes.length, filename, mime: mime);

  Future<JobStatus> jobStatus(String id) async {
    final j = await _send('GET', 'api/jobs/$id') as Map;
    return JobStatus(
      status: j['status'] as String? ?? 'queued',
      stage: j['stage'] as String? ?? '',
      progress: (j['progress'] as num?)?.toDouble() ?? 0,
      result: (j['result'] as Map?)?.cast<String, dynamic>(),
      error: j['error'] as String?,
    );
  }

  /// A finished analysis by id, e.g. an item found by a Feed check.
  Future<Map<String, dynamic>> result(String id) async => ((await _send('GET', 'api/results/$id')) as Map)['result'].cast<String, dynamic>();

  Future<void> sendFeedback(String jobId, String rating, {String? correctedMood}) =>
      _send('POST', 'api/feedback/$jobId', body: {'rating': rating, 'corrected_mood': correctedMood});

  // ---------------- account ----------------
  Future<({List<Plan> plans, bool demo})> plans() async {
    final j = await _send('GET', 'api/plans') as Map;
    return (plans: (j['plans'] as List).whereType<Map>().map((p) => Plan.fromJson(p.cast<String, dynamic>())).toList(), demo: j['payments'] != 'live');
  }

  /// Creates the account; returns the new session token and the account details.
  Future<({String token, Me me})> signup({required String name, required String email, required String password, String? device}) async {
    final j = await _send('POST', 'api/auth/signup', body: {'name': name, 'email': email, 'password': password, 'device': device ?? ''}) as Map;
    return (token: j['token'] as String, me: Me.fromJson((j['me'] as Map).cast<String, dynamic>()));
  }

  Future<({String token, Me me})> login({required String email, required String password, String? device}) async {
    final j = await _send('POST', 'api/auth/login', body: {'email': email, 'password': password, 'device': device ?? ''}) as Map;
    return (token: j['token'] as String, me: Me.fromJson((j['me'] as Map).cast<String, dynamic>()));
  }

  Future<void> logout() => _send('POST', 'api/auth/logout');
  Future<Me> me() async => Me.fromJson(((await _send('GET', 'api/me')) as Map).cast<String, dynamic>());
  Future<Me> updateName(String name) async => Me.fromJson(((await _send('PUT', 'api/me', body: {'name': name})) as Map).cast<String, dynamic>());
  Future<void> changePassword(String current, String next) => _send('POST', 'api/me/password', body: {'current': current, 'new': next});

  Future<({Me me, String? message})> subscribe(String plan, String cycle) async {
    final j = await _send('POST', 'api/me/subscribe', body: {'plan': plan, 'cycle': cycle}) as Map;
    return (me: Me.fromJson((j['me'] as Map).cast<String, dynamic>()), message: j['message'] as String?);
  }

  Future<Me> cancelPlan() async => Me.fromJson((((await _send('POST', 'api/me/cancel')) as Map)['me'] as Map).cast<String, dynamic>());
  Future<void> deleteAccount(String password) => _send('POST', 'api/me/delete', body: {'password': password});

  // ---------------- feed checks, monitoring, alerts (each person only ever sees their own) ----------------
  Future<dynamic> owner(String method, String path, {Object? body}) => _send(method, path, body: body);

  // `platform` is the site: ig (Instagram, the default), yt, tt or fb.
  Future<Map<String, dynamic>> session(String pid, {String platform = 'ig'}) async => ((await owner('GET', 'api/sessions/$pid?platform=$platform')) as Map).cast<String, dynamic>();
  Future<void> startLogin(String pid, {String platform = 'ig'}) => owner('POST', 'api/sessions/$pid/login?platform=$platform');
  Future<void> cancelLogin(String pid, {String platform = 'ig'}) => owner('POST', 'api/sessions/$pid/login/cancel?platform=$platform');
  Future<void> markConnected(String pid, {String platform = 'ig'}) => owner('POST', 'api/sessions/$pid/connected?platform=$platform');
  /// Hands the server the session the phone just signed in to.
  Future<void> importSession(String pid, List<Map<String, dynamic>> cookies, {String platform = 'ig'}) => owner('POST', 'api/sessions/$pid/import', body: {'cookies': cookies, 'platform': platform});
  Future<void> disconnect(String pid, {String platform = 'ig'}) => owner('DELETE', 'api/sessions/$pid?platform=$platform');
  Future<String> viewToken(String pid, {String platform = 'ig'}) async => ((await owner('POST', 'api/sessions/$pid/view-token?platform=$platform')) as Map)['token'] as String;

  /// WebSocket address of the streamed private browser.
  Uri viewSocket(String pid, String token) {
    final u = uri('api/sessions/$pid/view', {'t': token});
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws');
  }

  Future<List<MonitorSettings>> monitors() async => ((await owner('GET', 'api/monitors')) as List).whereType<Map>().map((m) => MonitorSettings.fromJson(m.cast<String, dynamic>())).toList();

  Future<MonitorSettings> saveMonitor(String pid, {required String name, required bool enabled, required int intervalMin, required bool consent, String platform = 'ig'}) async =>
      MonitorSettings.fromJson(((await owner('PUT', 'api/monitors/$pid', body: {'name': name, 'enabled': enabled, 'interval_min': intervalMin, 'consent': consent, 'platform': platform})) as Map).cast<String, dynamic>());

  Future<String> startScan(String pid, String kind, {List<String> terms = const [], int limit = 10, String platform = 'ig'}) async =>
      ((await owner('POST', 'api/scans', body: {'profile': pid, 'kind': kind, 'terms': terms, 'limit': limit, 'platform': platform})) as Map)['id'] as String;

  Future<ScanReport> scan(String id) async => ScanReport.fromJson(((await owner('GET', 'api/scans/$id')) as Map).cast<String, dynamic>());
  Future<List<ScanReport>> scans(String pid, {String? platform}) async => ((await owner('GET', 'api/scans?profile=$pid${platform != null ? '&platform=$platform' : ''}')) as List).whereType<Map>().map((m) => ScanReport.fromJson(m.cast<String, dynamic>())).toList();

  Future<({List<AlertItem> alerts, int unread})> alerts({String? profile, int limit = 50}) async {
    final j = await owner('GET', 'api/alerts?limit=$limit${profile != null ? '&profile=$profile' : ''}') as Map;
    return (alerts: ((j['alerts'] as List?) ?? const []).whereType<Map>().map((a) => AlertItem.fromJson(a.cast<String, dynamic>())).toList(), unread: (j['unread'] as num?)?.toInt() ?? 0);
  }

  Future<void> markAlertsRead([List<String> ids = const []]) => owner('POST', 'api/alerts/read', body: {'ids': ids});

  void close() => _http.close();
}

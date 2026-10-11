import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurolens/core/api.dart';
import 'package:neurolens/core/settings.dart';
import 'package:neurolens/core/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testUid = 'abcd1234';

/// A result shaped like the real backend's (video).
Map<String, dynamic> sampleResult({String dominant = 'happy', bool image = false, Map<String, double>? averages}) {
  final moods = ['confident', 'motivated', 'focused', 'inspired', 'excited', 'happy', 'funny', 'romantic', 'hungry', 'peaceful', 'heartbroken', 'sad', 'angry', 'lost', 'tired', 'depressed'];
  final avg = averages ?? {for (final m in moods) m: m == dominant ? 46.0 : 3.0};
  return {
    'kind': image ? 'image' : 'video',
    'confidence': {'level': 'clear', 'margin': 30.2},
    'safety': {'checked': true, 'level': 'clear', 'flags': [], 'frames_checked': 8},
    'duration_seconds': 24.5,
    'frames_analyzed': 30,
    'timeline': image ? [] : [for (var i = 0; i < 6; i++) {'t': i * 4.0, for (final m in moods) m: m == dominant ? 0.4 + i * 0.01 : 0.03}],
    'averages': avg,
    'visual_averages': avg,
    'audio': {'available': !image, 'dominant': 'happy', 'averages': avg, 'loudness_db': -18.2},
    'dominant_mood': dominant,
    'color_metrics': {'avg_brightness': 55.0, 'avg_saturation': 42.0, 'cuts_per_minute': 18.0},
    'verdict': 'This feels like a $dominant reel.',
    'mood_labels': {'happy': 'Fun / Trending Reels'},
    'keyframes': [
      {'t': 3.0, 'mood': dominant, 'score': 60.0, 'url': 'api/keyframes/abc/0.jpg'},
      {'t': 9.0, 'mood': dominant, 'score': 55.0, 'url': 'api/keyframes/abc/1.jpg'},
    ],
    'source': {'kind': 'link', 'url': 'https://www.instagram.com/reel/AAAAA1/', 'title': 'A test reel'},
  };
}

final planCatalogue = [
  {'id': 'free', 'name': 'Starter', 'monthly': 0, 'yearly': 0, 'quota': 5, 'history': 10, 'children': 0, 'weekly': false, 'seats': 1, 'blurb': 'Analyze your own Reels and images.', 'features': ['5 analyses / month'], 'off': ['Child profiles and monitoring']},
  {'id': 'pro', 'name': 'Creator & Family', 'monthly': 12, 'yearly': 9, 'quota': 100, 'history': 200, 'children': 3, 'weekly': true, 'seats': 1, 'featured': true, 'blurb': 'For creators and parents.', 'features': ['100 analyses / month', '3 child profiles'], 'off': []},
  {'id': 'studio', 'name': 'Studio', 'monthly': 39, 'yearly': 29, 'quota': 500, 'history': 1000, 'children': 10, 'weekly': true, 'seats': 5, 'blurb': 'For teams.', 'features': ['500 analyses / month'], 'off': []},
];

/// What GET /api/me returns.
Map<String, dynamic> meJson({String plan = 'free', int used = 0, String name = 'Alice', String email = 'alice@example.com', int childrenUsed = 0}) {
  final p = planCatalogue.firstWhere((e) => e['id'] == plan);
  final quota = p['quota'] as int;
  return {
    'userId': testUid,
    'name': name,
    'email': email,
    'plan': p,
    'cycle': 'monthly',
    'used': used,
    'quota': quota,
    'remaining': (quota - used).clamp(0, quota),
    'resetsOn': '2026-11-01',
    'childrenUsed': childrenUsed,
    'childrenAllowed': p['children'],
  };
}

/// Settings for a phone that is signed in (or not), with the intro already seen.
Future<AppSettings> makeSettings({String server = 'http://192.168.1.5:8000', String? token = 'test-session', bool intro = true, Map<String, Object> extra = const {}}) async {
  SharedPreferences.setMockInitialValues({if (server.isNotEmpty) 'baseUrl': server, if (intro) 'introSeen': true, ...extra});
  return AppSettings(await SharedPreferences.getInstance(), tokens: MemoryTokenStore(token), sessionToken: token);
}

class Recorded {
  Recorded(this.request, this.body);
  final http.BaseRequest request;
  final String body;
}

/// An ApiClient whose HTTP calls go to [handler], and a log of what was sent. The account endpoints (`/api/me`, `/api/plans`)
/// are answered for you (a user on [plan]) unless you pass `answerAccount: false`.
Future<(ApiClient, List<Recorded>, AppSettings)> fakeApi(
  Future<http.Response> Function(http.Request r) handler, {
  String? token = 'test-session',
  String plan = 'free',
  int used = 0,
  bool intro = true,
  bool answerAccount = true,
  Map<String, Object> prefs = const {},
}) async {
  final settings = await makeSettings(token: token, intro: intro, extra: prefs);
  final log = <Recorded>[];
  final client = MockClient.streaming((req, bodyStream) async {
    final bytes = await bodyStream.toBytes();
    log.add(Recorded(req, utf8.decode(bytes, allowMalformed: true)));
    final r = http.Request(req.method, req.url)..headers.addAll(req.headers);
    if (!(req.headers['content-type'] ?? '').startsWith('multipart')) r.bodyBytes = bytes;
    http.Response res;
    if (answerAccount && req.method == 'GET' && req.url.path.endsWith('/api/me')) {
      res = json(meJson(plan: plan, used: used));
    } else if (answerAccount && req.method == 'GET' && req.url.path.endsWith('/api/plans')) {
      res = json({'plans': planCatalogue, 'payments': 'demo'});
    } else {
      res = await handler(r);
    }
    return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode, headers: res.headers);
  });
  return (ApiClient(settings, client: client), log, settings);
}

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

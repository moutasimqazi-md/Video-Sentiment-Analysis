import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurolens/core/api.dart';
import 'package:neurolens/core/models.dart';
import 'package:neurolens/core/settings.dart';
import 'package:neurolens/core/stores.dart';
import 'package:neurolens/core/token_store.dart';
import 'package:neurolens/core/wellbeing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  group('server address', () {
    test('the NeuroLens server is built in, so nothing has to be typed', () async {
      SharedPreferences.setMockInitialValues({});
      final fresh = AppSettings(await SharedPreferences.getInstance(), tokens: MemoryTokenStore());
      expect(fresh.baseUrl, 'https://absurd-chasing-deflector.ngrok-free.dev');
      expect(fresh.isCustomServer, isFalse);
      await fresh.setBaseUrl('192.168.1.20:8000');
      expect(fresh.baseUrl, 'http://192.168.1.20:8000');
      expect(fresh.isCustomServer, isTrue);
      await fresh.useDefaultServer();
      expect(fresh.baseUrl, AppSettings.defaultServer);
      await fresh.setBaseUrl(AppSettings.defaultServer); // typing the built-in address is the same as having none
      expect(fresh.isCustomServer, isFalse);
    });

    test('adds a scheme and strips trailing slashes', () {
      expect(AppSettings.normalizeUrl('my-site.ngrok-free.dev/'), 'https://my-site.ngrok-free.dev');
      expect(AppSettings.normalizeUrl('192.168.1.20:8000'), 'http://192.168.1.20:8000');
      expect(AppSettings.normalizeUrl('10.0.2.2:8000//'), 'http://10.0.2.2:8000');
      expect(AppSettings.normalizeUrl('localhost:8000'), 'http://localhost:8000');
      expect(AppSettings.normalizeUrl('  https://a.b/c  '), 'https://a.b/c');
      expect(AppSettings.normalizeUrl(''), '');
    });
  });

  group('analysis result', () {
    test('reads a real-shaped video result', () {
      final r = AnalysisResult(sampleResult());
      expect(r.dominant, 'happy');
      expect(r.isImage, isFalse);
      expect(r.ranked().first.key, 'happy');
      expect(r.timeline.length, 6);
      expect(r.keyframes.length, 2);
      expect(r.safety!.checked, isTrue);
      expect(r.safety!.flagged, isFalse);
      expect(r.confidenceLevel, 'clear');
      expect(r.pace, 'Medium');
      expect(r.audioAvailable, isTrue);
      expect(r.sourceTitle, 'A test reel');
    });

    test('reads an image result and survives missing fields', () {
      final r = AnalysisResult({'kind': 'image', 'averages': {'sad': 70, 'happy': 10}});
      expect(r.isImage, isTrue);
      expect(r.dominant, 'sad');
      expect(r.timeline, isEmpty);
      expect(r.keyframes, isEmpty);
      expect(r.safety, isNull);
      expect(r.audioAvailable, isFalse);
      expect(r.verdict, '');
    });

    test('a flagged frame is reported', () {
      final raw = sampleResult()..['safety'] = {'checked': true, 'level': 'review', 'frames_checked': 8, 'flags': [{'label': 'Revealing or suggestive content', 'frames': 3, 'of': 8, 'score': 99.1, 't': 4.0}]};
      final s = AnalysisResult(raw).safety!;
      expect(s.flagged, isTrue);
      expect(s.flags.first.frames, 3);
    });
  });

  group('wellbeing signal (kept in sync with the web app and server)', () {
    test('light content is calm', () => expect(Wellbeing.assess({'happy': 60, 'funny': 20}, 'happy').level, WellbeingLevel.calm));
    test('heavy tone is flagged', () {
      expect(Wellbeing.assess({'sad': 30, 'depressed': 25}, 'sad').level, WellbeingLevel.high);
      expect(Wellbeing.assess({'sad': 26, 'lost': 5}, 'sad').level, WellbeingLevel.watch);
    });
    test('a strongly heavy dominant mood alone is worth a look', () => expect(Wellbeing.assess({'tired': 40}, 'tired').level, WellbeingLevel.watch));
    test('rollup counts levels and averages the mix', () {
      final roll = WellbeingRollup.of([{'happy': 80.0}, {'sad': 40.0, 'depressed': 30.0}], ['happy', 'sad']);
      expect(roll.count, 2);
      expect(roll.high, 1);
      expect(roll.heavyShare, 50);
      expect(roll.overall, WellbeingLevel.high);
    });
  });

  group('scan report', () {
    test('detail and list shapes both parse', () {
      final detail = ScanReport.fromJson({
        'id': 'abc', 'profile': 'me', 'kind': 'profile', 'createdAt': 1.0, 'finishedAt': 2.0, 'status': 'done', 'stage': 'Done', 'progress': 1.0,
        'items': [{'url': 'u', 'kind': 'reel', 'ok': true, 'jobId': 'j', 'mood': 'sad', 'level': 'watch', 'safety': 'clear'}, {'url': 'v', 'kind': 'post', 'ok': false}],
        'summary': {'analyzed': 1, 'lines': ['Checked 1 item.'], 'moods': [['sad', 100]], 'review': ['Clear theme'], 'username': 'tester'},
      });
      expect(detail.items.length, 2);
      expect(detail.analyzed, 1);
      expect(detail.moodMix.first.key, 'sad');
      expect(detail.username, 'tester');
      final list = ScanReport.fromJson({'id': 'abc', 'profile': 'me', 'kind': 'explore', 'status': 'running', 'items': 4, 'summary': null});
      expect(list.items, isEmpty);
      expect(list.running, isTrue);
    });
  });

  group('API client', () {
    test('sends a link to analyze, with the ngrok header and JSON body', () async {
      final (api, log, _) = await fakeApi((r) async => json({'job_id': 'job1'}));
      expect(await api.analyzeLink('https://www.instagram.com/reel/AAAAA1/'), 'job1');
      final sent = log.single;
      expect(sent.request.url.toString(), 'http://192.168.1.5:8000/api/analyze-link');
      expect(sent.request.headers['ngrok-skip-browser-warning'], '1');
      expect(jsonDecode(sent.body), {'url': 'https://www.instagram.com/reel/AAAAA1/'});
    });

    test('every call carries the signed-in session; a signed-out phone sends none', () async {
      final (api, log, _) = await fakeApi((r) async => json({'ok': true}), token: 'session-123');
      await api.ping();
      expect(log.single.request.headers['X-User-Token'], 'session-123');
      final (anon, anonLog, _) = await fakeApi((r) async => json({'ok': true}), token: null);
      await anon.ping();
      expect(anonLog.single.request.headers.containsKey('X-User-Token'), isFalse);
    });

    test('sign up and sign in send the details and read the account back', () async {
      final (api, log, _) = await fakeApi((r) async => json({'token': 'new-token', 'me': meJson(plan: 'free', name: 'Alice')}), token: null);
      final up = await api.signup(name: 'Alice', email: 'alice@example.com', password: 'correct horse 1', device: 'Android phone');
      expect(up.token, 'new-token');
      expect(up.me.displayName, 'Alice');
      expect(up.me.plan.id, 'free');
      expect(up.me.remaining, 5);
      expect(jsonDecode(log.first.body), {'name': 'Alice', 'email': 'alice@example.com', 'password': 'correct horse 1', 'device': 'Android phone'});
      final inn = await api.login(email: 'alice@example.com', password: 'correct horse 1');
      expect(inn.token, 'new-token');
      expect(log.last.request.url.path, '/api/auth/login');
    });

    test('plans and subscription changes', () async {
      final (api, log, _) = await fakeApi((r) async => r.url.path.endsWith('/subscribe') ? json({'me': meJson(plan: 'pro'), 'demo': true, 'message': 'Demo mode: switched on without a charge.'}) : json({}));
      final plans = await api.plans();
      expect(plans.plans.map((p) => p.id), ['free', 'pro', 'studio']);
      expect(plans.demo, isTrue);
      expect(plans.plans[1].children, 3);
      final r = await api.subscribe('pro', 'yearly');
      expect(r.me.plan.id, 'pro');
      expect(r.message, contains('Demo mode'));
      expect(jsonDecode(log.last.body), {'plan': 'pro', 'cycle': 'yearly'});
    });

    test('deleting the account sends the password', () async {
      final (api, log, _) = await fakeApi((r) async => json({'ok': true}));
      await api.deleteAccount('my password');
      expect(log.single.request.url.path, '/api/me/delete');
      expect(jsonDecode(log.single.body), {'password': 'my password'});
    });

    test('server errors surface their message', () async {
      final (api, _, _) = await fakeApi((r) async => json({'detail': 'Only YouTube and Instagram links are supported'}, 400));
      await expectLater(api.analyzeLink('https://example.com'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Only YouTube and Instagram links are supported')));
    });

    test('a refused session tells the app to sign in again', () async {
      final (api, _, _) = await fakeApi((r) async => json({'detail': 'Please sign in again.'}, 401));
      var expired = 0;
      api.onSessionExpired = () => expired++;
      await expectLater(api.alerts(), throwsA(isA<ApiException>().having((e) => e.unauthorized, 'unauthorized', true)));
      expect(expired, 1);
    });

    test('a wrong password is not mistaken for an expired session', () async {
      final (api, _, _) = await fakeApi((r) async => json({'detail': 'Incorrect email or password.'}, 401), token: null);
      var expired = 0;
      api.onSessionExpired = () => expired++;
      await expectLater(api.login(email: 'a@b.co', password: 'x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Incorrect email or password.')));
      expect(expired, 0);
    });

    test('hitting the plan limit is recognised', () async {
      final (api, _, _) = await fakeApi((r) async => json({'detail': "You have used this month's 5 analyses on the Starter plan. Upgrade or wait until it resets."}, 402));
      await expectLater(api.analyzeLink('https://www.instagram.com/reel/AAAAA1/'), throwsA(isA<ApiException>().having((e) => e.planLimit, 'planLimit', true)));
    });

    test('an unreachable server gives a friendly message', () async {
      final (api, _, _) = await fakeApi((r) async => throw Exception('socket'));
      await expectLater(api.jobStatus('x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains("Can't reach"))));
    });

    test('uploads a file as multipart with its name and type', () async {
      final (api, log, _) = await fakeApi((r) async => json({'job_id': 'up1'}));
      final id = await api.uploadFile(Uint8List.fromList(List.filled(64, 7)), 'clip.mp4', mime: 'video/mp4');
      expect(id, 'up1');
      final req = log.single;
      expect(req.request.headers['content-type'], startsWith('multipart/form-data'));
      expect(req.body, contains('filename="clip.mp4"'));
      expect(req.body, contains('content-type: video/mp4'));
    });

    test('builds server-relative image URLs and the websocket address', () async {
      final (api, _, _) = await fakeApi((r) async => json({}));
      expect(api.absolute('api/keyframes/abc/0.jpg'), 'http://192.168.1.5:8000/api/keyframes/abc/0.jpg');
      expect(api.thumbnailUrl('abc'), 'http://192.168.1.5:8000/api/thumbnails/abc.jpg');
      expect(api.viewSocket('me', 'tok').toString(), 'ws://192.168.1.5:8000/api/sessions/me/view?t=tok');
    });

    test('a secure server uses wss for the private browser', () async {
      final settings = await makeSettings(server: 'https://x.ngrok-free.dev');
      expect(ApiClient(settings).viewSocket('c1', 't').toString(), 'wss://x.ngrok-free.dev/api/sessions/c1/view?t=t');
    });

    test('probe accepts a NeuroLens server and rejects anything else', () async {
      final (good, _, _) = await fakeApi((r) async => json({'learning': true, 'rated_examples': 3}));
      expect(await good.probe('http://x'), isTrue);
      final (bad, _, _) = await fakeApi((r) async => http.Response('<html>nope</html>', 200));
      expect(await bad.probe('http://x'), isFalse);
    });
  });

  group('stores', () {
    test('history keeps the newest first, caps its size and survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final h = HistoryStore(prefs, userId: 'u1')..limit = 50;
      for (var i = 0; i < 55; i++) {
        await h.add(HistoryEntry(id: 'id$i', createdAt: i, title: 't$i', profileId: 'me', result: sampleResult()));
      }
      expect(h.items.length, 50); // the plan's history limit
      expect(h.items.first.id, 'id54');
      final again = HistoryStore(prefs, userId: 'u1');
      expect(again.items.length, 50);
      await again.remove(again.items.first.id);
      expect(again.items.length, 49);
    });

    test('a corrupt save does not crash the app', () async {
      SharedPreferences.setMockInitialValues({'history_u1': '{not json', 'children_u1': '[1,2'});
      final prefs = await SharedPreferences.getInstance();
      expect(HistoryStore(prefs, userId: 'u1').items, isEmpty);
      expect(ProfilesStore(prefs, userId: 'u1').children, isEmpty);
    });

    test('two accounts on one phone never see each other\'s history or children', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final h = HistoryStore(prefs, userId: 'alice');
      final p = ProfilesStore(prefs, userId: 'alice');
      await h.add(HistoryEntry(id: 'a1', createdAt: 1, title: "Alice's reel", profileId: 'me', result: sampleResult()));
      await p.add('Sam', 12);
      h.switchUser('bob');
      p.switchUser('bob');
      expect(h.items, isEmpty);
      expect(p.children, isEmpty);
      h.switchUser(null);
      expect(h.items, isEmpty); // signed out: nothing is shown
      h.switchUser('alice');
      p.switchUser('alice');
      expect(h.items.single.title, "Alice's reel");
      expect(p.children.single.name, 'Sam');
    });

    test('child profile ids are valid for the server', () async {
      SharedPreferences.setMockInitialValues({});
      final p = ProfilesStore(await SharedPreferences.getInstance(), userId: 'u1');
      final c = await p.add('  Sam ', 12);
      expect(c.name, 'Sam');
      expect(RegExp(r'^[a-z0-9_-]{1,40}$').hasMatch(c.id), isTrue);
      await p.setActive(c.id);
      await p.remove(c.id);
      expect(p.active, 'me');
    });
  });

  group('job queue', () {
    test('a link goes from sent, to running, to saved in history', () async {
      var polls = 0;
      final (api, _, settings) = await fakeApi((r) async {
        if (r.url.path.endsWith('analyze-link')) return json({'job_id': 'abcdef0123456789abcdef0123456789'});
        polls++;
        return polls < 2 ? json({'status': 'running', 'stage': 'Scoring frames (4/12)', 'progress': 0.4}) : json({'status': 'done', 'stage': 'Done', 'progress': 1.0, 'result': sampleResult(dominant: 'peaceful')});
      });
      final history = HistoryStore(settings.prefs);
      final queue = JobQueue(api, history);
      final done = queue.onDone.first;
      final job = await queue.addLink('https://www.instagram.com/reel/AAAAA1/', profileId: 'me');
      expect(job.serverId, 'abcdef0123456789abcdef0123456789');
      final finished = await done.timeout(const Duration(seconds: 15));
      expect(finished.state, JobState.done);
      expect(history.items.single.analysis.dominant, 'peaceful');
      expect(history.items.single.title, 'A test reel'); // the server's title replaces the raw link
      queue.dispose();
    });

    test('a failed analysis shows its error and can be retried', () async {
      final (api, _, settings) = await fakeApi((r) async => r.url.path.endsWith('analyze-link') ? json({'job_id': 'j1'}) : json({'status': 'error', 'error': "We couldn't analyze that video."}));
      final queue = JobQueue(api, HistoryStore(settings.prefs));
      final job = await queue.addLink('https://www.instagram.com/reel/AAAAA1/', profileId: 'me');
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(job.state, JobState.error);
      expect(job.error, contains("couldn't analyze"));
      expect(queue.active, isEmpty);
      queue.dispose();
    });

    test('a rejected upload fails immediately with the server message', () async {
      final (api, _, settings) = await fakeApi((r) async => json({'detail': 'Unsupported file type: .gif'}, 400));
      final queue = JobQueue(api, HistoryStore(settings.prefs));
      final job = await queue.addFile(() => Stream.value([1, 2, 3]), 3, 'a.gif', profileId: 'me', mime: 'image/gif');
      expect(job.state, JobState.error);
      expect(job.error, 'Unsupported file type: .gif');
      queue.dispose();
    });
  });
}

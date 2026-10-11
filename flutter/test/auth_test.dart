import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/auth.dart';
import 'package:neurolens/core/api.dart';
import 'package:neurolens/core/models.dart';
import 'package:neurolens/core/settings.dart';
import 'package:neurolens/core/stores.dart';
import 'package:neurolens/core/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Future<(AuthController, ApiClient, AppSettings, HistoryStore, ProfilesStore, JobQueue)> make(Future<dynamic> Function(String path, String method) handler,
    {String? token = 'tok', String plan = 'free', Map<String, Object> prefs = const {}}) async {
  final (api, _, settings) = await fakeApi((r) async {
    final res = await handler(r.url.path, r.method);
    return res ?? json({});
  }, token: token, plan: plan, prefs: prefs);
  final history = HistoryStore(settings.prefs);
  final profiles = ProfilesStore(settings.prefs);
  final jobs = JobQueue(api, history);
  return (AuthController(api, settings, history, profiles, jobs), api, settings, history, profiles, jobs);
}

void main() {
  test('a saved session is checked on launch and the account is loaded', () async {
    final (auth, _, _, history, _, _) = await make((p, m) async => null, plan: 'pro');
    expect(auth.status, AuthStatus.starting);
    await auth.restore();
    expect(auth.signedIn, isTrue);
    expect(auth.me!.plan.id, 'pro');
    expect(auth.offline, isFalse);
    history.switchUser(testUid); // the history shown is this account's
    expect(history.limit, 200); // pro keeps 200 analyses
  });

  test('no saved session means signed out', () async {
    final (auth, _, _, _, _, _) = await make((p, m) async => null, token: null);
    await auth.restore();
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.me, isNull);
  });

  test('a session the server rejects signs out with a notice', () async {
    final (api, _, settings) = await fakeApi((r) async => json({'detail': 'Please sign in again.'}, 401), answerAccount: false);
    final history = HistoryStore(settings.prefs);
    final auth = AuthController(api, settings, history, ProfilesStore(settings.prefs), JobQueue(api, history));
    await auth.restore();
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.notice, 'Please sign in again.');
    expect(settings.isSignedIn, isFalse); // the dead session is forgotten
  });

  test('no connection keeps the saved account so the app still opens (offline)', () async {
    // first launch online to cache the account, then the server disappears
    final (api, _, settings) = await fakeApi((r) async => json({}));
    final history = HistoryStore(settings.prefs);
    final auth = AuthController(api, settings, history, ProfilesStore(settings.prefs), JobQueue(api, history));
    await auth.restore();
    expect(auth.signedIn, isTrue);
    final (offlineApi, _, _) = await fakeApi((r) async => throw Exception('no network'), answerAccount: false, prefs: {'me_cache': (await SharedPreferences.getInstance()).getString('me_cache')!});
    final offHistory = HistoryStore(settings.prefs);
    final auth2 = AuthController(offlineApi, settings, offHistory, ProfilesStore(settings.prefs), JobQueue(offlineApi, offHistory));
    await auth2.restore();
    expect(auth2.signedIn, isTrue);
    expect(auth2.offline, isTrue);
    expect(auth2.me!.displayName, 'Alice');
  });

  test('signing in stores the session and loads that account\'s data', () async {
    final (api, _, settings) = await fakeApi((r) async => r.url.path.endsWith('/login') ? json({'token': 'fresh-token', 'me': meJson(name: 'Alice')}) : json({}), token: null);
    SharedPreferences.setMockInitialValues({'history_$testUid': '[]'});
    final history = HistoryStore(settings.prefs);
    final profiles = ProfilesStore(settings.prefs);
    final auth = AuthController(api, settings, history, profiles, JobQueue(api, history));
    await auth.restore();
    expect(auth.status, AuthStatus.signedOut);
    await auth.login(email: ' Alice@Example.com ', password: 'correct horse 1');
    expect(auth.signedIn, isTrue);
    expect(settings.sessionToken, 'fresh-token');
    expect(auth.me!.email, 'alice@example.com');
  });

  test('a wrong password leaves the phone signed out and shows the server message', () async {
    final (api, _, settings) = await fakeApi((r) async => json({'detail': 'Incorrect email or password.'}, 401), token: null);
    final history = HistoryStore(settings.prefs);
    final auth = AuthController(api, settings, history, ProfilesStore(settings.prefs), JobQueue(api, history));
    await expectLater(auth.login(email: 'a@b.co', password: 'nope nope'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Incorrect email or password.')));
    expect(auth.signedIn, isFalse);
    expect(settings.isSignedIn, isFalse);
  });

  test('signing out clears the session and hides the data, which stays for next time', () async {
    final (auth, _, settings, history, profiles, _) = await make((p, m) async => null);
    await auth.restore();
    await history.add(HistoryEntry(id: 'h1', createdAt: 1, title: 'Mine', profileId: 'me', result: sampleResult()));
    await profiles.add('Sam', 12);
    await auth.logout();
    expect(auth.status, AuthStatus.signedOut);
    expect(settings.isSignedIn, isFalse);
    expect(history.items, isEmpty);
    expect(profiles.children, isEmpty);
    // signing back in as the same account brings it back
    history.switchUser(testUid);
    profiles.switchUser(testUid);
    expect(history.items.single.title, 'Mine');
    expect(profiles.children.single.name, 'Sam');
  });

  test('the server ending the session (signed out elsewhere) signs the app out', () async {
    final (auth, api, settings, _, _, _) = await make((p, m) async => json({'detail': 'Please sign in again.'}, 401));
    await auth.restore();
    expect(auth.signedIn, isTrue);
    await expectLater(api.alerts(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.notice, contains('signed out'));
    expect(settings.isSignedIn, isFalse);
  });

  test('changing plan updates the allowance and how much history is kept', () async {
    final (api, _, settings) = await fakeApi((r) async => r.url.path.endsWith('/subscribe') ? json({'me': meJson(plan: 'pro'), 'demo': true, 'message': 'Demo mode'}) : json({}));
    final history = HistoryStore(settings.prefs);
    final auth = AuthController(api, settings, history, ProfilesStore(settings.prefs), JobQueue(api, history));
    await auth.restore();
    expect(history.limit, 10);
    final msg = await auth.subscribe('pro', 'monthly');
    expect(msg, 'Demo mode');
    expect(auth.me!.plan.id, 'pro');
    expect(auth.me!.quota, 100);
    expect(history.limit, 200);
  });

  test('deleting the account removes it here too', () async {
    final (auth, _, settings, history, profiles, _) = await make((p, m) async => p.endsWith('/delete') ? json({'ok': true}) : null);
    await auth.restore();
    await history.add(HistoryEntry(id: 'h1', createdAt: 1, title: 'Mine', profileId: 'me', result: sampleResult()));
    await profiles.add('Sam', 12);
    await auth.deleteAccount('my password');
    expect(auth.status, AuthStatus.signedOut);
    expect(settings.isSignedIn, isFalse);
    final prefs = settings.prefs;
    expect(prefs.getString('history_$testUid'), isNull);
    expect(prefs.getString('children_$testUid'), isNull);
    expect(prefs.getString('me_cache'), isNull);
  });

  test('a wrong password does not delete anything', () async {
    final (auth, _, settings, _, _, _) = await make((p, m) async => p.endsWith('/delete') ? json({'detail': 'That password is wrong.'}, 403) : null);
    await auth.restore();
    await expectLater(auth.deleteAccount('wrong'), throwsA(isA<ApiException>()));
    expect(auth.signedIn, isTrue);
    expect(settings.isSignedIn, isTrue);
  });

  test('the session is kept in the secure store, not in plain preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryTokenStore();
    final settings = AppSettings(await SharedPreferences.getInstance(), tokens: store);
    await settings.setSession('secret-session');
    expect(await store.read(), 'secret-session');
    expect(settings.prefs.getKeys().any((k) => (settings.prefs.get(k) ?? '').toString().contains('secret-session')), isFalse);
    await settings.setSession(null);
    expect(await store.read(), isNull);
  });
}

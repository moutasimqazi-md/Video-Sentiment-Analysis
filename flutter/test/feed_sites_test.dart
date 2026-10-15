// Feed check for Instagram, YouTube, TikTok and Facebook on the phone: the site list (mirrors backend/neurolens/platforms.py), that every call
// names its site (and still means Instagram when it doesn't), that the models carry it, and the real Feed screen with its site picker.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/models.dart';
import 'package:neurolens/core/platforms.dart';
import 'package:neurolens/main.dart';
import 'package:neurolens/ui/screens/private_browser.dart';

import 'helpers.dart';
import 'private_browser_test.dart' show FakeSocket;

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// The Feed screen loads its session, monitors and scans from the server before it draws; give those calls time to answer.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  group('the site list', () {
    test('four sites, in the server\'s order, each with its own checks', () {
      expect(sites.map((s) => s.code).toList(), ['ig', 'yt', 'tt', 'fb']);
      expect(sites.map((s) => s.name).toList(), ['Instagram', 'YouTube', 'TikTok', 'Facebook']);
      List<String> ids(String c) => siteOf(c).modes.map((m) => m.id).toList();
      expect(ids('ig'), ['explore', 'foryou', 'terms', 'profile']);
      expect(ids('yt'), ['foryou', 'history', 'terms']);
      expect(ids('tt'), ['foryou', 'explore', 'terms']);
      expect(ids('fb'), ['foryou', 'explore', 'terms']);
      expect(siteOf('yt').mode('history').label, 'Watch history');
      expect(siteOf('tt').modes.any((m) => m.id == 'profile'), isFalse, reason: 'only Instagram has an account review');
    });

    test('signed in means what the server means by it', () {
      expect(siteOf('ig').signedIn(['sessionid']), isTrue);
      expect(siteOf('tt').signedIn(['sid_tt']), isTrue);
      expect(siteOf('yt').signedIn(['SAPISID']), isTrue);
      expect(siteOf('yt').signedIn(['__Secure-3PSID']), isTrue);
      expect(siteOf('fb').signedIn(['c_user', 'xs']), isTrue);
      expect(siteOf('fb').signedIn(['c_user']), isFalse, reason: 'Facebook needs both cookies');
      expect(siteOf('ig').signedIn(['sid_tt']), isFalse, reason: "another site's cookie is not a sign-in");
      expect(siteOf('ig').signedIn([]), isFalse);
    });

    test('login and security pages are recognised as unfinished', () {
      expect(siteOf('ig').isPending('https://www.instagram.com/accounts/login/?next=/'), isTrue);
      expect(siteOf('fb').isPending('https://www.facebook.com/checkpoint/123'), isTrue);
      expect(siteOf('tt').isPending('https://www.tiktok.com/login?x=1'), isTrue);
      expect(siteOf('tt').isPending('https://www.tiktok.com/foryou'), isFalse);
      expect(siteOf('fb').isPending('https://www.facebook.com/watch/'), isFalse);
    });

    test('YouTube uses the server\'s private browser because Google refuses web-view sign-in; the others sign in on the phone', () {
      expect(siteOf('yt').phoneSignIn, isFalse);
      for (final c in ['ig', 'tt', 'fb']) {
        expect(siteOf(c).phoneSignIn, isTrue, reason: c);
      }
      expect(siteOf('yt').note, contains('Google'));
      expect(siteOf('ig').loginUrl, 'https://www.instagram.com/accounts/login/');
      expect(siteOf('tt').loginUrl, 'https://www.tiktok.com/login');
      expect(siteOf('fb').loginUrl, 'https://www.facebook.com/login/');
    });

    test('an unknown code falls back to Instagram', () {
      expect(siteOf('zz').code, 'ig');
      expect(siteOf(null).code, 'ig');
    });
  });

  group('every call names its site', () {
    test('sessions, sign-in and disconnect carry the site, and mean Instagram when none is given', () async {
      final (api, log, _) = await fakeApi((r) async => json({'connected': null, 'login': {'state': 'idle'}, 'token': 't'}), token: 'owner');
      await api.session('me');
      await api.session('me', platform: 'tt');
      await api.startLogin('kid1', platform: 'fb');
      await api.cancelLogin('me', platform: 'yt');
      await api.markConnected('me', platform: 'tt');
      await api.disconnect('me', platform: 'fb');
      await api.viewToken('me', platform: 'yt');
      final q = log.map((l) => '${l.request.method} ${l.request.url.path} ${l.request.url.queryParameters['platform']}').toList();
      expect(log.where((l) => l.request.method == 'GET').map((l) => l.request.url.queryParameters['platform']).toList(), ['ig', 'tt'], reason: 'GET: Instagram when none is given, then TikTok');
      expect(q, contains('POST /api/sessions/kid1/login fb'));
      expect(q, contains('POST /api/sessions/me/login/cancel yt'));
      expect(q, contains('POST /api/sessions/me/connected tt'));
      expect(q, contains('DELETE /api/sessions/me fb'));
      expect(q, contains('POST /api/sessions/me/view-token yt'));
    });

    test('importing a phone sign-in, scans and monitors carry the site', () async {
      final (api, log, _) = await fakeApi((r) async => json({'id': 'a' * 32, 'profile_id': 'kid1', 'platform': 'tt', 'enabled': 0, 'interval_min': 120, 'consent': true, 'connected': false}), token: 'owner');
      await api.importSession('me', [{'name': 'sessionid', 'value': 'x'}], platform: 'tt');
      await api.startScan('me', 'foryou', terms: ['a'], limit: 6, platform: 'yt');
      await api.startScan('me', 'explore');
      final m = await api.saveMonitor('kid1', name: 'Sam', enabled: false, intervalMin: 120, consent: true, platform: 'tt');
      Map body(int i) => jsonDecode(log[i].body) as Map;
      expect(body(0)['platform'], 'tt');
      expect(body(0)['cookies'], isNotEmpty);
      expect(body(1), {'profile': 'me', 'kind': 'foryou', 'terms': ['a'], 'limit': 6, 'platform': 'yt'});
      expect(body(2)['platform'], 'ig', reason: 'older call sites still mean Instagram');
      expect(body(3)['platform'], 'tt');
      expect(m.platform, 'tt');
    });

    test('scans can be listed for one site or all of a profile\'s sites', () async {
      final (api, log, _) = await fakeApi((r) async => json([]), token: 'owner');
      await api.scans('me');
      await api.scans('me', platform: 'tt');
      expect(log[0].request.url.queryParameters, {'profile': 'me'});
      expect(log[1].request.url.queryParameters, {'profile': 'me', 'platform': 'tt'});
    });
  });

  group('models', () {
    test('alerts, scans and monitors know their site, and default to Instagram', () {
      final a = AlertItem.fromJson({'id': '1', 'profile': 'kid1', 'platform': 'fb', 'createdAt': 1, 'level': 'watch', 'kind': 'digest', 'title': 't', 'body': 'b', 'seen': false});
      expect(a.platform, 'fb');
      final s = ScanReport.fromJson({'id': '2', 'profile': 'me', 'platform': 'yt', 'kind': 'history', 'status': 'done', 'items': 3});
      expect(s.platform, 'yt');
      final m = MonitorSettings.fromJson({'profile_id': 'kid1', 'platform': 'tt', 'enabled': 1, 'interval_min': 60, 'consent': true, 'connected': true});
      expect(m.platform, 'tt');
      expect(AlertItem.fromJson({'id': '1', 'createdAt': 1, 'title': 't', 'body': 'b'}).platform, 'ig', reason: 'an older server sends no site');
      expect(ScanReport.fromJson({'id': '2'}).platform, 'ig');
      expect(MonitorSettings.fromJson({'profile_id': 'me'}).platform, 'ig');
    });
  });

  group('the private browser follows the site', () {
    test('it starts the right site, asks for its key, and shows its address', () async {
      final paths = <String>[];
      final (api, _, _) = await fakeApi((r) async {
        paths.add('${r.method} ${r.url.path}?${r.url.query}');
        return r.url.path.endsWith('/view-token') ? json({'token': 'tok'}) : json({'state': 'starting'});
      }, token: 'owner');
      final c = PrivateBrowserController(api: api, profileId: 'me', platform: 'yt', connector: (u) => FakeSocket());
      expect(c.host, 'youtube.com');
      await c.start();
      expect(paths, contains('POST /api/sessions/me/login?platform=yt'));
      expect(paths, contains('POST /api/sessions/me/view-token?platform=yt'));
      c.dispose();
      expect(PrivateBrowserController(api: api, profileId: 'me').host, 'instagram.com');
      expect(PrivateBrowserController(api: api, profileId: 'me', platform: 'tt').host, 'tiktok.com');
    });
  });

  group('the Feed screen', () {
    Future<(dynamic, dynamic, List<Recorded>)> signedIn({List<Map<String, dynamic>> children = const []}) async {
      final (api, log, settings) = await fakeApi((r) async {
        if (r.url.path.endsWith('/api/monitors')) return json([]);
        if (r.url.path.contains('/api/sessions/')) return json({'connected': null, 'login': {'state': 'idle', 'error': null}, 'platform': r.url.queryParameters['platform']});
        if (r.url.path.contains('/api/scans')) return json([]);
        if (r.url.path.contains('/api/alerts')) return json({'alerts': [], 'unread': 0});
        return json({});
      }, plan: 'pro', prefs: {if (children.isNotEmpty) 'children': jsonEncode(children)});
      return (api, settings, log);
    }

    Future<void> openFeed(WidgetTester tester, dynamic api, dynamic settings) async {
      await tester.pumpWidget(NeuroLensApp(settings: settings, api: api, launch: false));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(find.text('Feed').last);
      await settle(tester);
    }

    String platformsAsked(List<Recorded> log) => log.where((l) => l.request.url.path == '/api/sessions/me').map((l) => l.request.url.queryParameters['platform']).join(',');

    testWidgets('shows all four sites, starts on Instagram, and each site shows its own checks and sign-in', (tester) async {
      phone(tester);
      final (api, settings, log) = await signedIn();
      await openFeed(tester, api, settings);
      for (final n in ['Instagram', 'YouTube', 'TikTok', 'Facebook']) {
        expect(find.widgetWithText(ChoiceChip, n), findsOneWidget, reason: n);
      }
      expect(find.text('Sign in to Instagram'), findsOneWidget);
      expect(platformsAsked(log), 'ig');

      await tester.tap(find.widgetWithText(ChoiceChip, 'TikTok'));
      await settle(tester);
      expect(find.text('Sign in to TikTok'), findsOneWidget);
      expect(find.text('Sign in to Instagram'), findsNothing);
      expect(platformsAsked(log), 'ig,tt', reason: 'switching site asks the server about that site');

      await tester.tap(find.widgetWithText(ChoiceChip, 'YouTube'));
      await settle(tester);
      expect(find.text('Sign in to YouTube'), findsOneWidget);
      expect(find.textContaining('Google sometimes refuses'), findsOneWidget);
      expect(find.textContaining('private browser'), findsWidgets, reason: 'YouTube signs in through the server\'s private browser');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Facebook'));
      await settle(tester);
      expect(find.text('Sign in to Facebook'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the checks offered follow the site once signed in', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async {
        if (r.url.path.endsWith('/api/monitors')) return json([]);
        if (r.url.path.contains('/api/sessions/')) return json({'connected': 1760000000, 'login': {'state': 'idle', 'error': null}});
        if (r.url.path.contains('/api/scans')) return json([]);
        if (r.url.path.contains('/api/alerts')) return json({'alerts': [], 'unread': 0});
        return json({});
      }, plan: 'pro');
      await openFeed(tester, api, settings);
      expect(find.text('Instagram connected'), findsOneWidget);
      expect(find.text('Account review'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'YouTube'));
      await settle(tester);
      expect(find.text('YouTube connected'), findsOneWidget);
      expect(find.text('Watch history'), findsOneWidget);
      expect(find.text('Home recommendations'), findsOneWidget);
      expect(find.text('Account review'), findsNothing, reason: 'YouTube has no account review');
      await tester.tap(find.widgetWithText(ChoiceChip, 'TikTok'));
      await settle(tester);
      expect(find.text('For You'), findsWidgets);
      expect(find.text('Watch history'), findsNothing);
      expect(log.where((l) => l.request.method == 'POST').isEmpty, isTrue, reason: 'browsing sites starts nothing');
      expect(tester.takeException(), isNull);
    });
  });
}

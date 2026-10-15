import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/api.dart';
import 'package:neurolens/core/models.dart';
import 'package:neurolens/core/settings.dart';
import 'package:neurolens/main.dart';
import 'package:neurolens/ui/screens/launch.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void phone(WidgetTester tester, {double w = 390, double h = 844}) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Starts the app straight at the sign-in gate (no splash) and lets the saved session load.
Future<void> boot(WidgetTester tester, ApiClient api, AppSettings settings, {bool launch = false}) async {
  await tester.pumpWidget(NeuroLensApp(settings: settings, api: api, launch: launch));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Map<String, dynamic> entryJson(String id, String title, String dominant, {String profile = 'me', int createdAt = 1760000000000}) =>
    HistoryEntry(id: id, createdAt: createdAt, title: title, profileId: profile, result: sampleResult(dominant: dominant)).toJson();

Map<String, Object> seed(List<Map<String, dynamic>> items) => {'history_$testUid': jsonEncode(items)};

void main() {
  group('opening the app', () {
    testWidgets('splash, then the sign-in screen for someone signed out', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => json({'learning': true}), token: null);
      await tester.pumpWidget(NeuroLensApp(settings: settings, api: api));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Know what a video makes people feel'), findsOneWidget); // the splash
      expect(find.text('Connecting…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    });

    testWidgets('a saved session goes straight to the app after the splash', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async => json({'learning': true}));
      await tester.pumpWidget(NeuroLensApp(settings: settings, api: api));
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Analyze a video or image'), findsOneWidget);
      expect(find.textContaining('Alice'), findsWidgets); // greeted by name
      expect(log.any((l) => l.request.url.path.endsWith('/api/me')), isTrue);
    });

    testWidgets('an unreachable server is explained, with Try again and Continue', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => throw Exception('offline'), token: null, answerAccount: false);
      await tester.pumpWidget(NeuroLensApp(settings: settings, api: api));
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Can't reach NeuroLens right now."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('the intro is shown once to a new account, and can be skipped', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => json({}), intro: false);
      await boot(tester, api, settings);
      expect(find.text('Know what a video makes people feel'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Look after what your family watches'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Analyze a video or image'), findsOneWidget);
      expect(settings.introSeen, isTrue);
    });
  });

  group('sign in and sign up', () {
    testWidgets('validation: nothing is sent until the details look right', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async => json({}), token: null);
      await boot(tester, api, settings);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      await tester.tap(find.text('Create account').first);
      await tester.pump();
      expect(find.text('Your name'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(find.text('Enter your name.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Alice');
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'alice@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(log.any((l) => l.request.url.path.contains('/auth/')), isFalse);
    });

    testWidgets('sign up needs the terms ticked, then signs in and shows the intro', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async => r.url.path.endsWith('/signup') ? json({'token': 'new-session', 'me': meJson()}) : json({}), token: null, intro: false);
      await boot(tester, api, settings);
      await tester.tap(find.text('Create account').first);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Alice');
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'alice@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'correct horse 1');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(find.textContaining('agree to the Terms'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(settings.sessionToken, 'new-session');
      expect(log.firstWhere((l) => l.request.url.path.endsWith('/signup')).body, contains('"email":"alice@example.com"'));
      expect(find.text('Know what a video makes people feel'), findsOneWidget); // the intro, because this account is new on this phone
    });

    testWidgets('an email that is already registered shows the server message', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => json({'detail': 'An account with this email already exists. Sign in instead.'}, 409), token: null);
      await boot(tester, api, settings);
      await tester.tap(find.text('Create account').first);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Alice');
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'alice@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'correct horse 1');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('An account with this email already exists. Sign in instead.'), findsOneWidget);
    });

    testWidgets('a wrong password shows the message and stays on the screen; the right one opens the app', (tester) async {
      phone(tester);
      var correct = false;
      final (api, _, settings) = await fakeApi((r) async => r.url.path.endsWith('/login') ? (correct ? json({'token': 'session-x', 'me': meJson()}) : json({'detail': 'Incorrect email or password.'}, 401)) : json({}), token: null);
      await boot(tester, api, settings);
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'alice@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(settings.isSignedIn, isFalse);
      correct = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(settings.sessionToken, 'session-x');
      expect(find.text('Analyze a video or image'), findsOneWidget);
    });

    testWidgets('the password can be shown and hidden', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => json({}), token: null);
      await boot(tester, api, settings);
      expect(tester.widget<EditableText>(find.descendant(of: find.widgetWithText(TextFormField, 'Password'), matching: find.byType(EditableText))).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<EditableText>(find.descendant(of: find.widgetWithText(TextFormField, 'Password'), matching: find.byType(EditableText))).obscureText, isFalse);
    });

    testWidgets('being signed out elsewhere returns to sign-in with an explanation', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => r.url.path.endsWith('/alerts') ? json({'detail': 'Please sign in again.'}, 401) : json({}));
      await boot(tester, api, settings);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.textContaining('signed out'), findsOneWidget);
      expect(settings.isSignedIn, isFalse);
    });
  });

  group('the app', () {
    testWidgets('home shows an empty state, then a mood mix once there is history', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => json({}));
      await boot(tester, api, settings);
      expect(find.text('Get started'), findsOneWidget);
      expect(find.textContaining('Starter · 5 of 5 analyses left'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Looking after a child?'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Looking after a child?'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // a fresh app, so the stores are rebuilt from storage
      final (api2, _, s2) = await fakeApi((r) async => json({}), prefs: seed([entryJson('a' * 32, 'Sunset reel', 'peaceful')]));
      await boot(tester, api2, s2);
      await tester.scrollUntilVisible(find.text('Your mood mix'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Your mood mix'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Sunset reel'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Sunset reel'), findsOneWidget);
    });

    testWidgets('analyze: validates links, queues one, and shows progress then a notice with View', (tester) async {
      phone(tester);
      var polls = 0;
      final (api, log, settings) = await fakeApi((r) async {
        if (r.url.path.endsWith('analyze-link')) return json({'job_id': 'b' * 32});
        polls++;
        return polls < 2 ? json({'status': 'running', 'stage': 'Scoring frames (4/12)', 'progress': 0.3}) : json({'status': 'done', 'stage': 'Done', 'progress': 1.0, 'result': sampleResult(dominant: 'funny')});
      });
      await boot(tester, api, settings);
      await tester.tap(find.text('Analyze').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Who is this for?'), findsOneWidget);
      expect(find.text('5 of 5 analyses left this month'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Analyze'));
      await tester.pump();
      expect(find.text('Paste a link first.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'not a link');
      await tester.tap(find.widgetWithText(FilledButton, 'Analyze'));
      await tester.pump();
      expect(find.text('Paste full links starting with https://'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'https://www.instagram.com/reel/AAAAA1/');
      await tester.tap(find.widgetWithText(FilledButton, 'Analyze'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(log.any((l) => l.request.url.path.endsWith('analyze-link') && l.request.headers['X-User-Token'] == 'test-session'), isTrue, reason: 'the session is sent so the server counts it');
      await tester.scrollUntilVisible(find.text('Your analyses'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Your analyses'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('A test reel is ready'), findsOneWidget);
      await tester.tap(find.widgetWithText(SnackBarAction, 'View'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('Dominant emotion'), findsOneWidget);
    });

    testWidgets('analyze: out of analyses on the plan -> an upgrade prompt that opens the plans', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async => json({}), used: 5);
      await boot(tester, api, settings);
      await tester.tap(find.text('Analyze').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("You've used all 5 analyses this month"), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'https://www.instagram.com/reel/AAAAA1/');
      await tester.tap(find.widgetWithText(FilledButton, 'Analyze'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Upgrade your plan'), findsOneWidget);
      expect(log.any((l) => l.request.url.path.endsWith('analyze-link')), isFalse, reason: 'nothing is sent when the plan has no analyses left');
      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Your plan: Starter'), findsOneWidget);
    });

    testWidgets('analyze: the server refusing for the plan limit is explained on the job, with See plans', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => json({'detail': "You have used this month's 5 analyses on the Starter plan. Upgrade or wait until it resets."}, 402), used: 0);
      await boot(tester, api, settings);
      await tester.tap(find.text('Analyze').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'https://www.instagram.com/reel/AAAAA1/');
      await tester.tap(find.widgetWithText(FilledButton, 'Analyze'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.scrollUntilVisible(find.textContaining('Upgrade or wait until it resets'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Upgrade or wait until it resets'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'See plans'), findsOneWidget);
    });

    testWidgets('results: the full report on a small phone, and feedback reaches the server', (tester) async {
      phone(tester, w: 320, h: 640);
      final (api, log, settings) = await fakeApi((r) async => json({'ok': true}), prefs: seed([entryJson('c' * 32, 'A very long reel title that should wrap nicely across lines', 'excited')]));
      await boot(tester, api, settings);
      await tester.scrollUntilVisible(find.text('History'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('A very long reel title'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Dominant emotion'), findsOneWidget);
      for (final label in ['Key moments', 'Emotional profile', 'Emotion timeline', 'Visual check', 'Wellbeing signal', 'Was this accurate?']) {
        await tester.scrollUntilVisible(find.text(label), 300, scrollable: find.byType(Scrollable).first);
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Spot on'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.firstWhere((l) => l.request.url.path.contains('/api/feedback/')).body, contains('"rating":"good"'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('history: search and filters narrow the list; swipe deletes with undo', (tester) async {
      phone(tester);
      final items = [entryJson('1' * 32, 'Beach day', 'happy'), entryJson('2' * 32, 'Late night thoughts', 'sad'), entryJson('3' * 32, 'Pasta recipe', 'hungry')];
      final (api, _, settings) = await fakeApi((r) async => json({}), prefs: seed(items), plan: 'pro');
      await boot(tester, api, settings);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Beach day'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'pasta');
      await tester.pump();
      expect(find.text('Beach day'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No matches'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.drag(find.text('Beach day'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Beach day'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Beach day'), findsOneWidget);
    });

    testWidgets('family: the free plan has no child profiles and offers an upgrade', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => json({}));
      await boot(tester, api, settings);
      await tester.tap(find.text('Family'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Add a child'));
      await tester.pumpAndSettle();
      expect(find.textContaining('has no child profiles'), findsOneWidget);
      expect(find.text('See plans'), findsOneWidget);
    });

    testWidgets('family: a paid plan can add a child, and stops at the plan limit', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => json({}), plan: 'pro');
      await boot(tester, api, settings);
      await tester.tap(find.text('Family'));
      await tester.pump(const Duration(milliseconds: 300));
      for (final n in ['Sam', 'Ana', 'Lee']) {
        await tester.tap(find.byType(FloatingActionButton).evaluate().isNotEmpty ? find.byType(FloatingActionButton) : find.text('Add a child'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Name or nickname'), n);
        await tester.tap(find.text('Add profile'));
        await tester.pumpAndSettle();
        expect(find.text(n), findsOneWidget);
      }
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('includes 3 child profiles'), findsOneWidget);
    });

    testWidgets('alerts: listed for the signed-in user, marked read, and opened from the server', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async {
        if (r.url.path.endsWith('/alerts')) {
          return json({
            'unread': 1,
            'alerts': [
              {'id': 'a1', 'profile': 'me', 'createdAt': DateTime.now().millisecondsSinceEpoch / 1000 - 300, 'level': 'high', 'kind': 'item', 'title': "High concern: Sam's feed", 'body': 'A sad reel has a heavy emotional tone.', 'link': 'pages/results.html?id=${'e' * 32}', 'jobId': 'e' * 32, 'scanId': 's', 'seen': false},
            ]
          });
        }
        if (r.url.path.contains('/api/results/')) return json({'id': 'e' * 32, 'result': sampleResult(dominant: 'sad')});
        return json({'ok': true});
      });
      await boot(tester, api, settings);
      await tester.tap(find.byTooltip('Account and settings'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text("High concern: Sam's feed"), findsOneWidget);
      await tester.tap(find.text("High concern: Sam's feed"));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(log.any((l) => l.request.url.path.endsWith('/alerts/read')), isTrue);
      expect(find.text('Dominant emotion'), findsOneWidget);
    });

    testWidgets('feed check is open to the signed-in user (no pairing step)', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async {
        if (r.url.path.contains('/api/sessions/')) return json({'connected': null, 'login': {'state': 'idle'}});
        if (r.url.path.endsWith('/api/monitors') || r.url.path.endsWith('/api/scans')) return json([]);
        return json({'alerts': [], 'unread': 0});
      });
      await boot(tester, api, settings);
      await tester.tap(find.text('Feed'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Sign in to Instagram'), findsOneWidget);
      expect(find.textContaining('Pair'), findsNothing);
    });
  });

  group('subscription', () {
    testWidgets('plans: shows usage and the plans, and switching to a paid plan calls the server (demo notice)', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async => r.url.path.endsWith('/subscribe') ? json({'me': meJson(plan: 'pro'), 'demo': true, 'message': 'Demo mode: your plan was switched on without a charge.'}) : json({}), used: 2);
      await boot(tester, api, settings);
      await tester.tap(find.byTooltip('Account and settings'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('Plans & usage'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Your plan: Starter'), findsOneWidget);
      expect(find.text('2 of 5 analyses used this month · resets 2026-11-01'), findsOneWidget);
      expect(find.text('Your current plan'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Choose Creator & Family'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Yearly · save 25%'));
      await tester.pump();
      expect(find.text('\$9'), findsOneWidget);
      await tester.tap(find.text('Choose Creator & Family'));
      await tester.pumpAndSettle();
      expect(find.text('Start Creator & Family'), findsOneWidget);
      expect(find.textContaining('Demo mode: this server does not take payments'), findsOneWidget);
      await tester.tap(find.text('Start plan'));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      final call = log.firstWhere((l) => l.request.url.path.endsWith('/subscribe'));
      expect(jsonDecode(call.body), {'plan': 'pro', 'cycle': 'yearly'});
      expect(find.textContaining('You are now on Creator & Family'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Your plan: Creator & Family'), -300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Your plan: Creator & Family'), findsOneWidget);
    });

    testWidgets('plans: switching back to Starter asks first and explains what stays', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async => r.url.path.endsWith('/cancel') ? json({'me': meJson(plan: 'free')}) : json({}), plan: 'pro');
      await boot(tester, api, settings);
      await tester.tap(find.byTooltip('Account and settings'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('Plans & usage'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('Switch to Starter'));
      await tester.pumpAndSettle();
      expect(find.text('Switch to Starter?'), findsOneWidget);
      expect(find.textContaining('Child monitoring beyond what this plan includes is paused'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(FilledButton, 'Switch to Starter')));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(log.any((l) => l.request.url.path.endsWith('/me/cancel')), isTrue);
      expect(find.text('Your plan: Starter'), findsOneWidget);
    });
  });

  group('account', () {
    Future<void> openAccount(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Account and settings'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('alice@example.com'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }

    testWidgets('shows who is signed in, and changing the password needs the current one', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async => r.url.path.endsWith('/password') ? (jsonDecode(utf8.decode(r.bodyBytes))['current'] == 'old password 1' ? json({'ok': true}) : json({'detail': 'Your current password is wrong.'}, 403)) : json({}));
      await boot(tester, api, settings);
      await openAccount(tester);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Starter plan'), findsOneWidget);
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Current password'), 'wrong');
      await tester.enterText(find.widgetWithText(TextField, 'New password'), 'brand new pass 1');
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      expect(find.text('Your current password is wrong.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Current password'), 'old password 1');
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Password changed'), findsOneWidget);
      expect(log.where((l) => l.request.url.path.endsWith('/me/password')).length, 2);
    });

    testWidgets('signing out returns to the sign-in screen and forgets the session', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async => json({'ok': true}), prefs: seed([entryJson('a' * 32, 'Mine', 'happy')]));
      await boot(tester, api, settings);
      await openAccount(tester);
      await tester.scrollUntilVisible(find.text('Sign out'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Welcome back'), findsOneWidget);
      expect(settings.isSignedIn, isFalse);
      expect(log.any((l) => l.request.url.path.endsWith('/auth/logout')), isTrue);
    });

    testWidgets('deleting the account needs the password, then returns to sign-in', (tester) async {
      phone(tester);
      final (api, log, settings) = await fakeApi((r) async => r.url.path.endsWith('/delete') ? (jsonDecode(utf8.decode(r.bodyBytes))['password'] == 'right password' ? json({'ok': true}) : json({'detail': 'That password is wrong.'}, 403)) : json({}));
      await boot(tester, api, settings);
      await openAccount(tester);
      await tester.scrollUntilVisible(find.text('Delete my account'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This permanently deletes your account'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Enter your password to confirm'), 'wrong');
      await tester.tap(find.widgetWithText(TextButton, 'Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('That password is wrong.'), findsOneWidget);
      expect(settings.isSignedIn, isTrue);
      await tester.enterText(find.widgetWithText(TextField, 'Enter your password to confirm'), 'right password');
      await tester.tap(find.widgetWithText(TextButton, 'Delete account'));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Your account was deleted.'), findsOneWidget);
      expect(settings.isSignedIn, isFalse);
      expect(log.where((l) => l.request.url.path.endsWith('/me/delete')).length, 2);
    });

    testWidgets('settings: the theme can be changed and there is no pairing or owner section', (tester) async {
      phone(tester);
      final (api, _, settings) = await fakeApi((r) async => json({}));
      await boot(tester, api, settings);
      await tester.tap(find.byTooltip('Account and settings'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.textContaining('Owner'), findsNothing);
      expect(find.textContaining('Pair'), findsNothing);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.dark);
      expect(tester.takeException(), isNull);
    });
  });

  test('the launcher accepts a custom splash time', () {
    expect(const Launcher(splashTime: Duration(milliseconds: 10)).splashTime.inMilliseconds, 10);
    SharedPreferences.setMockInitialValues({});
  });
}

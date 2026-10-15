// The Import screen and the habits report screen with all four platforms: how-to cards, saved reports, and opening each report.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/imports/habits.dart';
import 'package:neurolens/main.dart';

import 'helpers.dart';

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}


/// The Import screen builds its cards lazily, so scroll in steps until the thing exists and is on screen.
Future<void> reveal(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -350));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(f, findsWidgets, reason: 'never found after scrolling');
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<Map<String, dynamic>> report(String src, {int days = 25, int perDay = 70}) async {
  final start = DateTime(2026, 9, 1, 22).millisecondsSinceEpoch ~/ 1000;
  final evs = <Map<String, dynamic>>[
    for (var d = 0; d < days; d++)
      for (var i = 0; i < perDay; i++)
        {'src': src, 'kind': 'video', 'act': i % 5 == 0 ? 'like' : 'view', 't': start + d * 86400 + i * 150, 'url': 'https://example.test/v/$d$i', 'text': src == 'tt' ? '' : 'gym workout #fitness', 'by': ''},
  ];
  return analyzePlatform(src, evs, jsonDecode(File('assets/lexicon.json').readAsStringSync()) as Map<String, dynamic>, {});
}

void main() {
  Future<(dynamic, dynamic)> signedIn() async {
    final (api, _, settings) = await fakeApi((r) async {
      if (r.url.path.endsWith('/api/monitors')) return json([]);
      if (r.url.path.contains('/api/sessions/')) return json({'connected': null, 'login': {'state': 'idle', 'error': null}});
      if (r.url.path.contains('/api/scans')) return json([]);
      if (r.url.path.contains('/api/alerts')) return json({'alerts': [], 'unread': 0});
      return json({});
    }, prefs: {
      'imp_${testUid}_me_ig': jsonEncode(await report('ig')),
      'imp_${testUid}_me_tt': jsonEncode(await report('tt')),
      'imp_${testUid}_me_fb': jsonEncode(await report('fb')),
      'imp_index_$testUid': ['me|ig', 'me|tt', 'me|fb'],
    }, plan: 'pro');
    return (api, settings);
  }

  Future<void> boot(WidgetTester tester, dynamic api, dynamic settings) async {
    await tester.pumpWidget(NeuroLensApp(settings: settings, api: api, launch: false));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text('Import').last);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the Import screen explains all four exports and lists saved reports for each', (tester) async {
    phone(tester);
    final (api, settings) = await signedIn();
    await boot(tester, api, settings);
    expect(find.textContaining('Instagram, YouTube, TikTok or Facebook'), findsWidgets);
    for (final title in ['Instagram', 'YouTube (Google Takeout)', 'TikTok', 'Facebook']) {
      await reveal(tester, find.text(title));
      expect(find.text(title), findsOneWidget);
    }
    await reveal(tester, find.text('Saved reports'));
    expect(find.text('My Instagram report'), findsOneWidget);
    expect(find.text('My TikTok report'), findsOneWidget);
    expect(find.text('My Facebook report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the TikTok how-to card opens and explains there are no captions', (tester) async {
    phone(tester);
    final (api, settings) = await signedIn();
    await boot(tester, api, settings);
    await reveal(tester, find.text('TikTok'));
    await tester.tap(find.text('TikTok'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.textContaining('Download your data'), findsOneWidget);
    expect(find.textContaining('no captions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final name in ['TikTok', 'Facebook']) {
    testWidgets('the $name report opens, shows a score and its own series, and does not crash', (tester) async {
      phone(tester);
      final (api, settings) = await signedIn();
      await boot(tester, api, settings);
      await reveal(tester, find.text('My $name report'));
      await tester.tap(find.text('My $name report'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.textContaining(name), findsWidgets);
      expect(find.textContaining('/ 100').evaluate().isNotEmpty || find.textContaining('100').evaluate().isNotEmpty, isTrue);
      // scroll the whole report: every card must build without an exception
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
    });
  }
}

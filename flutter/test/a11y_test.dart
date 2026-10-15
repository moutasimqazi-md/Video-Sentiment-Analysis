import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/imports/habits.dart';
import 'package:neurolens/core/models.dart';
import 'package:neurolens/main.dart';

import 'helpers.dart';

/// Accessibility checks on every main screen: touch-target size, labelled controls, text contrast, and large text (no overflow).
Future<Map<String, Object>> _prefs() async {
  final start = DateTime(2026, 9, 1, 22).millisecondsSinceEpoch ~/ 1000;
  final evs = <Map<String, dynamic>>[
    for (var d = 0; d < 40; d++)
      for (var i = 0; i < 18 + d % 7; i++)
        {'src': 'ig', 'kind': 'reel', 'act': 'like', 't': start + d * 86400 + i * 420, 'url': 'https://www.instagram.com/reel/x$d$i/', 'text': i % 4 == 0 ? 'so sad and lonely tonight' : 'gym workout #fitness motivation', 'by': 'someone'}
  ];
  final rep = analyzePlatform('ig', evs, jsonDecode(File('assets/lexicon.json').readAsStringSync()) as Map<String, dynamic>, {});
  final items = [
    for (final (i, m) in ['happy', 'sad', 'hungry', 'excited'].indexed)
      HistoryEntry(id: '${i + 1}' * 32, createdAt: DateTime.now().subtract(Duration(days: i)).millisecondsSinceEpoch, title: 'Reel number ${i + 1}', profileId: 'me', result: sampleResult(dominant: m)).toJson()
  ];
  return {'history_$testUid': jsonEncode(items), 'imp_${testUid}_me_ig': jsonEncode(rep), 'imp_index_$testUid': ['me|ig']};
}

Future<void> tapText(WidgetTester t, String text, {bool last = false}) async {
  final all = find.text(text);
  if (all.evaluate().isEmpty || all.hitTestable().evaluate().isEmpty) {
    await t.scrollUntilVisible(all, 200, scrollable: find.byType(Scrollable).first);
  }
  // a match near the bottom edge sits under the navigation bar at large text sizes; scroll it back up clear of the bar
  final target = last ? all.last : all.first;
  if (t.getCenter(target).dy > t.view.physicalSize.height / t.view.devicePixelRatio - 120) {
    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    pos.jumpTo((pos.pixels - 240).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    await t.pumpAndSettle();
  }
  await t.tap(target);
}

void main() {
  Future<void> open(WidgetTester tester, {double text = 1}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final (api, _, settings) = await fakeApi((r) async {
      if (r.url.path.endsWith('/api/monitors')) return json([]);
      if (r.url.path.contains('/api/sessions/')) return json({'connected': null, 'login': {'state': 'idle', 'error': null}});
      if (r.url.path.contains('/api/scans')) return json([]);
      if (r.url.path.contains('/api/alerts')) return json({'alerts': [], 'unread': 0});
      return json({});
    }, prefs: await _prefs(), plan: 'pro');
    await tester.pumpWidget(NeuroLensApp(settings: settings, api: api, launch: false));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  final screens = <String, Future<void> Function(WidgetTester)>{
    'home': (t) async {},
    'analyze': (t) async {
      await t.tap(find.text('Analyze').last);
      await t.pump(const Duration(milliseconds: 400));
    },
    'import': (t) async {
      await t.tap(find.text('Import').last);
      await t.pump(const Duration(milliseconds: 400));
    },
    'feed': (t) async {
      await t.tap(find.text('Feed').last);
      await t.pump(const Duration(milliseconds: 600));
    },
    'family': (t) async {
      await t.tap(find.text('Family').last);
      await t.pump(const Duration(milliseconds: 400));
    },
    'account': (t) async {
      await t.tap(find.byTooltip('Account and settings'));
      await t.pumpAndSettle(const Duration(milliseconds: 300));
    },
    'plans': (t) async {
      await t.tap(find.byTooltip('Account and settings'));
      await t.pumpAndSettle(const Duration(milliseconds: 300));
      await tapText(t, 'Plans & usage');
      await t.pumpAndSettle(const Duration(milliseconds: 300));
    },
    'settings': (t) async {
      await t.tap(find.byTooltip('Account and settings'));
      await t.pumpAndSettle(const Duration(milliseconds: 300));
      await tapText(t, 'Settings');
      await t.pumpAndSettle(const Duration(milliseconds: 300));
    },
    'history': (t) async {
      await tapText(t, 'History');
      await t.pumpAndSettle(const Duration(milliseconds: 300));
    },
    'results': (t) async {
      await tapText(t, 'History');
      await t.pumpAndSettle(const Duration(milliseconds: 300));
      await t.tap(find.textContaining('Reel number 1'));
      await t.pumpAndSettle(const Duration(milliseconds: 300));
    },
    'habits report': (t) async {
      await t.tap(find.text('Import').last);
      await t.pump(const Duration(milliseconds: 400));
      await t.scrollUntilVisible(find.textContaining('My Instagram report'), 300, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('My Instagram report'), warnIfMissed: false);
      await t.pumpAndSettle(const Duration(milliseconds: 300));
    },
  };

  group('accessibility', () {
    for (final e in screens.entries) {
      testWidgets('${e.key}: tap targets, labels and contrast', (tester) async {
        final handle = tester.ensureSemantics();
        await open(tester);
        await e.value(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      testWidgets('${e.key}: large text (200%) does not overflow', (tester) async {
        await open(tester, text: 2);
        await e.value(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, nav) in screens.entries.where((e) => const ['home', 'analyze', 'import', 'feed', 'family', 'account', 'plans', 'history', 'results', 'habits report'].contains(e.key)).map((e) => (e.key, e.value))) {
      testWidgets('$name: dark theme contrast and tap targets', (tester) async {
        final handle = tester.ensureSemantics();
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await open(tester);
        await nav(tester);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });
    }
  });
}

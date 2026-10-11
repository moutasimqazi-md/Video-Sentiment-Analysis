import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/models.dart';
import 'package:neurolens/ui/screens/results_screen.dart';
import 'package:provider/provider.dart';
import 'package:neurolens/core/stores.dart';
import 'package:neurolens/ui/theme.dart';

import 'helpers.dart';

Map<String, dynamic> load(String name) => (jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map).cast<String, dynamic>();

void main() {
  for (final name in ['real_video', 'real_image']) {
    final fixture = load(name);
    final result = (fixture['result'] as Map).cast<String, dynamic>();

    test('$name: the app reads exactly what the real server sent', () {
      final r = AnalysisResult(result);
      expect(r.averages.length, 16);
      expect(r.dominant, isNotEmpty);
      expect(r.ranked().first.key, r.dominant);
      expect(r.confidenceLevel, isNotNull);
      expect(r.safety, isNotNull);
      expect(r.safety!.checked, isTrue);
      expect(r.wellbeing.label, isNotEmpty);
      if (r.isImage) {
        expect(r.timeline, isEmpty);
      } else {
        expect(r.timeline.length, greaterThan(5));
        expect(r.keyframes, isNotEmpty);
        expect(r.keyframes.first.url, startsWith('api/keyframes/'));
      }
    });

    testWidgets('$name: the results screen renders it on a small phone with no layout errors', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final (api, _, settings) = await fakeApi((r) async => json({}));
      final entry = HistoryEntry(id: fixture['id'] as String, createdAt: 1760000000000, title: 'Example', profileId: 'me', result: result, sourceUrl: 'https://www.instagram.com/reel/EXAMPLE/');
      await tester.pumpWidget(MultiProvider(
        providers: [Provider.value(value: api), ChangeNotifierProvider(create: (_) => HistoryStore(settings.prefs)), ChangeNotifierProvider(create: (_) => ProfilesStore(settings.prefs))],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: ResultsScreen(entry: entry)),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Dominant emotion'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Was this accurate?'), 400, scrollable: find.byType(Scrollable).first);
      expect(find.text('Was this accurate?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

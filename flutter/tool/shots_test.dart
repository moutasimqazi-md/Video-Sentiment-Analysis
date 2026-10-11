// Renders every main screen to PNG (real Roboto + Material Icons) so the UI can be reviewed without a phone.
// Run: flutter test tool/shots_test.dart   (images go to build/shots/)
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/imports/habits.dart';
import 'package:neurolens/core/models.dart';
import 'package:neurolens/main.dart';

import '../test/helpers.dart';

const _fonts = 'C:/src/flutter/bin/cache/artifacts/material_fonts';
final _key = GlobalKey();

Future<void> _loadFonts() async {
  Future<ByteData> bytes(String f) async => ByteData.sublistView(await File('$_fonts/$f').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(bytes('roboto-regular.ttf'))
    ..addFont(bytes('roboto-bold.ttf'))
    ..addFont(bytes('roboto-black.ttf'))
    ..addFont(bytes('roboto-medium.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(bytes('materialicons-regular.otf'));
  await icons.load();
}

void phone(WidgetTester tester, {double w = 390, double h = 844, double text = 1}) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> shoot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.runAsync(() async {
    final b = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/shots/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> boot(WidgetTester tester, dynamic api, dynamic settings, {bool launch = false}) async {
  await tester.pumpWidget(RepaintBoundary(key: _key, child: NeuroLensApp(settings: settings, api: api, launch: launch)));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Map<String, dynamic> entry(String id, String title, String dominant, int daysAgo) =>
    HistoryEntry(id: id, createdAt: DateTime.now().subtract(Duration(days: daysAgo)).millisecondsSinceEpoch, title: title, profileId: 'me', result: sampleResult(dominant: dominant)).toJson();

Future<Map<String, dynamic>> _report() async {
  final start = DateTime(2026, 9, 1, 22).millisecondsSinceEpoch ~/ 1000;
  final evs = <Map<String, dynamic>>[
    for (var d = 0; d < 40; d++)
      for (var i = 0; i < 18 + d % 7; i++)
        {'src': 'ig', 'kind': 'reel', 'act': 'like', 't': start + d * 86400 + i * 420, 'url': 'https://www.instagram.com/reel/x$d$i/', 'text': i % 4 == 0 ? 'so sad and lonely tonight' : 'gym workout #fitness motivation', 'by': 'someone'}
  ];
  return analyzePlatform('ig', evs, jsonDecode(File('assets/lexicon.json').readAsStringSync()) as Map<String, dynamic>, {});
}

Future<(dynamic, dynamic)> _signedIn({String plan = 'pro'}) async {
  final rep = await _report();
  final items = [entry('1' * 32, 'Beach day with friends', 'happy', 0), entry('2' * 32, 'Late night thoughts', 'sad', 1), entry('3' * 32, 'Pasta recipe', 'hungry', 3), entry('4' * 32, 'Gym motivation reel', 'excited', 5)];
  final (api, _, settings) = await fakeApi((r) async {
    if (r.url.path.endsWith('/api/monitors')) return json([]);
    if (r.url.path.contains('/api/sessions/')) return json({'connected': null, 'login': {'state': 'idle', 'error': null}});
    if (r.url.path.contains('/api/scans')) return json([]);
    if (r.url.path.contains('/api/alerts')) return json({'alerts': [], 'unread': 0});
    return json({});
  }, prefs: {'history_$testUid': jsonEncode(items), 'imp_${testUid}_me_ig': jsonEncode(rep), 'imp_index_$testUid': ['me|ig']}, plan: plan);
  return (api, settings);
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('shots: signed out', (tester) async {
    phone(tester);
    final (api, _, settings) = await fakeApi((r) async => json({}), token: null, intro: false);
    await tester.pumpWidget(RepaintBoundary(key: _key, child: NeuroLensApp(settings: settings, api: api)));
    await tester.pump(const Duration(milliseconds: 700));
    await shoot(tester, '01_splash');
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(milliseconds: 700));
    await shoot(tester, '02_signin');
    await tester.tap(find.textContaining('Create').first);
    await tester.pump(const Duration(milliseconds: 500));
    await shoot(tester, '03_signup');
  });

  testWidgets('shots: intro', (tester) async {
    phone(tester);
    final (api, _, settings) = await fakeApi((r) async => json({}), intro: false);
    await boot(tester, api, settings);
    await shoot(tester, '04_intro');
  });

  testWidgets('shots: tabs', (tester) async {
    phone(tester);
    final (api, settings) = await _signedIn();
    await boot(tester, api, settings);
    await shoot(tester, '10_home');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await shoot(tester, '11_home_scrolled');
    await tester.tap(find.text('Analyze').last);
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, '12_analyze');
    await tester.tap(find.text('Files'));
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, '13_analyze_files');
    await tester.tap(find.text('Import').last);
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, '14_import');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
    await shoot(tester, '15_import_scrolled');
    await tester.tap(find.text('Feed').last);
    await tester.pump(const Duration(milliseconds: 600));
    await shoot(tester, '16_feed');
    await tester.tap(find.text('Family').last);
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, '17_family');
  });

  testWidgets('shots: pages', (tester) async {
    phone(tester);
    final (api, settings) = await _signedIn();
    await boot(tester, api, settings);
    await tester.tap(find.byTooltip('Account and settings'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await shoot(tester, '18_account_menu');
    await tester.tap(find.text('Plans & usage'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await shoot(tester, '19_plans');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await shoot(tester, '20_settings');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('History').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await shoot(tester, '21_history');
    await tester.tap(find.textContaining('Beach day'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await shoot(tester, '22_results');
  });

  testWidgets('shots: habits report', (tester) async {
    phone(tester);
    final (api, settings) = await _signedIn();
    await boot(tester, api, settings);
    await tester.tap(find.text('Import').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('Saved reports'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.textContaining('My Instagram report'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await shoot(tester, '23_report');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await shoot(tester, '24_report_2');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await shoot(tester, '25_report_3');
  });
}

// TikTok and Facebook import on the phone. Mirrors frontend/tests/import-platforms.test.js so the website and the app behave the same.
// IMPORTANT: the TikTok and Facebook fixtures are *assumed* shapes (written from published descriptions and Meta's conventions), not real exports.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/imports/habits.dart';
import 'package:neurolens/core/imports/import_store.dart';
import 'package:neurolens/core/imports/parse.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 1, 10).millisecondsSinceEpoch ~/ 1000; // 2026-10-01 10:00:00 UTC

  Map<String, dynamic> tiktok() => {
        'Profile': {'Profile Information': {'ProfileMap': {'userName': 'someone', 'bioDescription': 'private bio'}}},
        'Direct Message': {'Direct Messages': {'ChatHistory': {'Chat with a friend': [{'Date': '2026-10-01 10:00:00', 'From': 'friend', 'Content': 'SECRET MESSAGE'}]}}},
        'Activity': {
          'Video Browsing History': {'VideoList': [
            {'Date': '2026-10-01 10:00:00', 'Link': 'https://www.tiktokv.com/share/video/7100000000000000001/'},
            {'Date': '2026-10-01 10:01:00', 'Link': 'https://www.tiktok.com/@some.user/video/7100000000000000002?is_from_webapp=1'},
          ]},
          'Like List': {'ItemFavoriteList': [{'date': '2026-10-02 11:00:00', 'link': 'https://www.tiktokv.com/share/video/7100000000000000003/'}]},
          'Favorite Videos': {'FavoriteVideoList': [{'Date': '2026-10-03 12:00:00', 'Link': 'https://www.tiktokv.com/share/video/7100000000000000004/'}]},
          'Search History': {'SearchList': [{'Date': '2026-10-04 13:00:00', 'SearchTerm': 'learn python'}, {'Date': '2026-10-04 13:05:00', 'SearchTerm': ''}]},
          'Share History': {'ShareHistoryList': [{'Date': '2026-10-05 14:00:00', 'SharedContent': 'video', 'Link': 'https://www.tiktokv.com/share/video/7100000000000000005/', 'Method': 'copy'}]},
          'Comments': {'CommentsList': [{'Date': '2026-10-06 15:00:00', 'Comment': 'great video', 'Url': 'https://www.tiktokv.com/share/video/7100000000000000006/'}]},
          'Login History': {'LoginHistoryList': [{'Date': '2026-10-07 16:00:00', 'IP': '203.0.113.9', 'DeviceModel': 'phone'}]},
        },
      };

  Map<String, dynamic> fbWatch() => {
        'watch_history_v2': [
          {'timestamp': t0, 'title': 'You watched a video from Some Page', 'attachments': [{'data': [{'external_context': {'url': 'https://www.facebook.com/watch/?v=111'}}]}]},
          {'timestamp': t0 + 60, 'title': 'You watched a reel', 'attachments': [{'data': [{'external_context': {'url': 'https://www.facebook.com/reel/222'}}]}]},
          {'timestamp': t0 + 120, 'title': 'no link and no text', 'data': []},
        ],
      };
  final fbLikes = {
    'likes_and_reactions_v2': [
      {'timestamp': t0, 'title': "Jane Doe liked Some Page's post", 'data': [{'reaction': {'reaction': 'LIKE', 'actor': 'Jane Doe'}}], 'attachments': [{'data': [{'external_context': {'url': 'https://www.facebook.com/somepage/videos/333'}}]}]},
      {'timestamp': t0 + 5, 'title': 'Jane Doe reacted', 'attachments': []},
    ],
  };
  final fbSearch = {
    'searches_v2': [
      {'timestamp': t0, 'data': [{'text': 'python tutorial'}], 'title': 'You searched for python tutorial'},
      {'timestamp': t0 + 1, 'title': 'You searched for cheap flights'},
    ],
  };

  group('TikTok', () {
    test('sections are recognised by name, with UTC times and rewritten video links', () {
      final ev = ttEvents(tiktok());
      List<Map<String, dynamic>> by(String a) => ev.where((e) => e['act'] == a).toList();
      expect(by('view').length, 2);
      expect(by('like').length, 1);
      expect(by('save').length, 1);
      expect(by('search').length, 1, reason: 'the empty search term is dropped');
      expect(by('share').length, 1);
      expect(by('comment').length, 1);
      expect(by('view')[0]['t'], t0);
      expect(by('view')[0]['url'], 'https://www.tiktok.com/@/video/7100000000000000001');
      expect(by('view')[1]['url'], 'https://www.tiktok.com/@/video/7100000000000000002');
      expect(by('search')[0]['text'], 'learn python');
      expect(ev.every((e) => e['src'] == 'tt'), isTrue);
    });

    test('direct messages, login history and profile details are never read', () {
      final dump = jsonEncode(ttEvents(tiktok()));
      expect(dump.contains('SECRET MESSAGE'), isFalse);
      expect(dump.contains('203.0.113.9'), isFalse);
      expect(dump.contains('private bio'), isFalse);
    });

    test('tolerates other key casing, epoch times, UTC suffixes and a different wrapper', () {
      final ev = ttEvents({
        'activity': {'watch history': {'videolist': [
          {'time': t0, 'url': 'https://www.tiktok.com/@a/video/7200000000000000001'},
          {'timestamp': '${t0 * 1000}', 'Link': 'https://vm.tiktok.com/ZMabc123/'},
          {'Date': '2026-10-01 10:00:00 UTC', 'Link': 'https://www.tiktok.com/@a/video/7200000000000000003'},
        ]}},
      });
      expect(ev.length, 3);
      expect(ev.every((e) => e['t'] == t0), isTrue);
      expect(ev[1]['url'], 'https://vm.tiktok.com/ZMabc123/', reason: 'short links are kept as they are');
    });

    test('nothing recognisable gives no events, and link rewriting matches the website', () {
      expect(ttEvents({'Settings': {'Foo': [{'bar': 1}]}}), isEmpty);
      expect(ttEvents(<String, dynamic>{}), isEmpty);
      expect(ttEvents(null), isEmpty);
      expect(ttUrl('https://www.tiktokv.com/share/video/7300000000000000009/'), 'https://www.tiktok.com/@/video/7300000000000000009');
      expect(ttUrl('https://www.tiktok.com/@x/video/7300000000000000009?lang=en'), 'https://www.tiktok.com/@/video/7300000000000000009');
      expect(ttUrl('https://vm.tiktok.com/ZM1/'), 'https://vm.tiktok.com/ZM1/');
      expect(ttUrl(''), '');
    });
  });

  group('Facebook', () {
    test('watched videos and reels, keeping a timed item with no link', () {
      final ev = fbEvents('fbWatched', fbWatch());
      expect(ev.length, 3);
      expect(ev.map((e) => [e['kind'], e['act'], e['src']]).toList(), [['video', 'view', 'fb'], ['reel', 'view', 'fb'], ['video', 'view', 'fb']]);
      expect(ev[0]['t'], t0);
      expect(ev[0]['url'], 'https://www.facebook.com/watch/?v=111', reason: 'links nested in attachments are found');
      expect(ev[2]['url'], '');
    });

    test('reactions keep the link but not the "Name liked ..." title', () {
      final ev = fbEvents('fbLikes', fbLikes);
      expect(ev.length, 2);
      expect(ev[0]['act'], 'like');
      expect(ev[0]['kind'], 'video');
      expect(ev.any((e) => (e['text'] as String).contains('Jane')), isFalse);
    });

    test('searches take the typed words', () {
      final ev = fbEvents('fbSearch', fbSearch);
      expect(ev.map((e) => e['text']).toList(), ['python tutorial', 'cheap flights']);
      expect(ev.every((e) => e['act'] == 'search' && e['url'] == ''), isTrue);
    });
  });

  test('file names map to the right category and private folders are never opened', () {
    expect(categorize('user_data_tiktok.json'), 'ttData');
    expect(categorize('TikTok/user_data.json'), 'ttData');
    expect(categorize('your_facebook_activity/watch/watch_history.json'), 'fbWatched');
    expect(categorize('your_facebook_activity/likes_and_reactions/posts_and_comments.json'), 'fbLikes');
    expect(categorize('search_history/your_search_history.json'), 'fbSearch');
    expect(categorize('your_instagram_activity/likes/liked_posts.json'), 'igLikes', reason: 'Instagram is unchanged');
    expect(categorize('Takeout/YouTube and YouTube Music/history/watch-history.json'), 'ytWatch', reason: 'YouTube is unchanged');
    expect(categorize('your_facebook_activity/messages/inbox/chat_1/message_1.json'), isNull);
    expect(categorize('notes.json'), isNull);
    for (final p in ['your_facebook_activity/messages/inbox/a/message_1.json', 'personal_information/profile_information/profile_information.json', 'friends_and_followers/friends.json', 'security_and_login_information/login.json']) {
      expect(isPrivatePath(p), isTrue, reason: p);
    }
    expect(importLabels['ttView'], 'Videos watched');
    expect(ImportStore.platforms, ['ig', 'yt', 'tt', 'fb']);
    expect(ImportStore.platformNames['tt'], 'TikTok');
    expect(ImportStore.platformNames['fb'], 'Facebook');
  });

  group('reading a real zip on disk', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('nl_imp4'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Map<String, dynamic>> read(Map<String, String> files) async {
      final arc = Archive();
      files.forEach((name, body) => arc.addFile(ArchiveFile.bytes(name, utf8.encode(body))));
      final zip = File('${dir.path}/export.zip')..writeAsBytesSync(ZipEncoder().encode(arc));
      return readExports([zip.path]);
    }

    test('four platforms in one zip: separate buckets, TikTok listed per kind, messages ignored', () async {
      final igLikes = {'likes_media_likes': [{'timestamp': t0, 'label_values': [{'label': 'URL', 'href': 'https://www.instagram.com/reel/AAA/'}, {'label': 'Caption', 'value': 'Learn Python #ai'}]}]};
      final r = await read({
        'instagram/your_instagram_activity/likes/liked_posts.json': jsonEncode(igLikes),
        'tiktok/user_data_tiktok.json': jsonEncode(tiktok()),
        'facebook/your_facebook_activity/watch/watch_history.json': jsonEncode(fbWatch()),
        'facebook/search/your_search_history.json': jsonEncode(fbSearch),
        'facebook/your_facebook_activity/messages/inbox/chat_1/message_1.json': '{"messages":[{"content":"SECRET FB MESSAGE"}]}',
      });
      final ev = (r['events'] as Map).cast<String, dynamic>();
      expect((ev['ig'] as List).length, 1);
      expect((ev['tt'] as List).length, 7);
      expect((ev['fb'] as List).length, 5);
      expect((ev['yt'] as List).length, 0);
      final ranges = (r['ranges'] as Map).keys.toSet();
      expect(ranges, {'igLikes', 'ttView', 'ttLike', 'ttSave', 'ttSearch', 'ttShare', 'ttComment', 'fbWatched', 'fbSearch'});
      expect(r['ignoredPrivate'], 1);
      expect(r['problems'], isEmpty);
      expect(jsonEncode(ev).contains('SECRET'), isFalse);
      expect((ev['tt'] as List).every((e) => !(e as Map).containsKey('_cat')), isTrue, reason: 'internal helper field is removed');
    });

    test('a TikTok file with nothing readable explains what to do; broken JSON does not crash', () async {
      final a = await read({'user_data.json': jsonEncode({'Settings': {'Foo': []}})});
      expect(((a['events'] as Map)['tt'] as List), isEmpty);
      expect((a['problems'] as List).first, contains('choose JSON'));
      final b = await read({'your_facebook_activity/watch/watch_history.json': '{not json'});
      expect(((b['events'] as Map)['fb'] as List), isEmpty);
      expect((b['problems'] as List).length, 1);
    });

    test('HTML Facebook and text TikTok exports are noticed, not silently dropped', () async {
      final r = await read({'your_facebook_activity/watch/watch_history.html': '<html></html>', 'user_data.txt': 'Date: 2026'});
      expect(r['sources'], 0);
      expect(r['fbHtml'], 1);
      expect(r['ttTxt'], 1);
    });
  });

  group('reports', () {
    final lexicon = jsonDecode(File('assets/lexicon.json').readAsStringSync()) as Map<String, dynamic>;
    List<Map<String, dynamic>> views(String src, int days, int perDay, {int startHour = 23}) {
      final start = DateTime(2026, 6, 1, startHour).millisecondsSinceEpoch ~/ 1000;
      return [
        for (var d = 0; d < days; d++)
          for (var i = 0; i < perDay; i++)
            {'src': src, 'kind': 'video', 'act': 'view', 't': start + d * 86400 + i * 120, 'url': 'https://www.$src.example/v/$d$i', 'text': '', 'by': ''}
      ];
    }

    test('TikTok and Facebook reports have a verdict, series and a storable shape', () {
      for (final src in ['tt', 'fb']) {
        final r = analyzePlatform(src, views(src, 20, 60), lexicon, {});
        final P = (r['platforms'] as Map)[src] as Map;
        final v = P['verdict'] as Map;
        expect((v['findings'] as List), isNotEmpty, reason: src);
        expect(v['score'], inInclusiveRange(0, 100));
        expect(((P['series'] as Map)['views'] as Map)['n'], 1200);
        expect(P.containsKey('searches'), isTrue);
        expect(P.containsKey('social'), isTrue);
        jsonEncode(r); // must be storable
      }
    });

    test('heavy TikTok watching is judged, and the tip names TikTok, not another app', () {
      final r = analyzePlatform('tt', views('tt', 20, 200), lexicon, {});
      final findings = (((r['platforms'] as Map)['tt'] as Map)['verdict'] as Map)['findings'] as List;
      final f = findings.cast<Map>().firstWhere((x) => x['id'] == 'tt-views');
      expect(f['severity'], anyOf('watch', 'high'));
      expect(f['tip'], contains('TikTok'));
    });

    test('Instagram and YouTube reports are unchanged by the refactor', () {
      final start = DateTime(2026, 6, 1, 23).millisecondsSinceEpoch ~/ 1000;
      final likes = [for (var d = 0; d < 10; d++) for (var i = 0; i < 40; i++) {'timestamp': start + d * 86400 + i * 300, 'label_values': [{'label': 'URL', 'href': 'https://www.instagram.com/reel/abc$d$i/'}, {'label': 'Caption', 'value': 'gym workout motivation #fitness'}]}];
      final evs = igEvents('igLikes', {'likes_media_likes': likes});
      expect(evs.length, 400);
      expect(evs.first['kind'], 'reel');
      expect(evs.first['text'], 'gym workout motivation #fitness');
      expect(evs.first['url'], 'https://www.instagram.com/reel/abc00/');
      final r = analyzePlatform('ig', evs, lexicon, {});
      expect((((r['platforms'] as Map)['ig'] as Map)['content'] as Map)['classified'], greaterThan(0));
    });
  });
}

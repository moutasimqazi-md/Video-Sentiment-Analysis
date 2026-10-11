import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurolens/core/imports/habits.dart';
import 'package:neurolens/core/imports/parse.dart';

void main() {
  final lexicon = File('assets/lexicon.json').readAsStringSync();

  List<Map<String, dynamic>> likes(int days, int perDay) {
    final start = DateTime(2026, 6, 1, 23).millisecondsSinceEpoch ~/ 1000;
    return [
      for (var d = 0; d < days; d++)
        for (var i = 0; i < perDay; i++)
          {'timestamp': start + d * 86400 + i * 300, 'label_values': [{'label': 'URL', 'href': 'https://www.instagram.com/reel/abc$d$i/'}, {'label': 'Caption', 'value': 'gym workout motivation #fitness'}]}
    ];
  }

  test('allowlist: private folders are never read, history files are', () {
    expect(categorize('your_instagram_activity/likes/liked_posts.json'), 'igLikes');
    expect(categorize('Takeout/YouTube and YouTube Music/history/watch-history.json'), 'ytWatch');
    expect(categorize('your_instagram_activity/messages/inbox/a/message_1.json'), isNull);
    expect(isPrivatePath('your_instagram_activity/messages/inbox/a/message_1.json'), isTrue);
    expect(isPrivatePath('personal_information/personal_information.json'), isTrue);
  });

  test('instagram likes parse and produce a report', () {
    final evs = igEvents('igLikes', {'likes_media_likes': likes(10, 40)});
    expect(evs.length, 400);
    expect(evs.first['kind'], 'reel');
    expect(evs.first['act'], 'like');
    final r = analyzePlatform('ig', evs, jsonDecode(lexicon) as Map<String, dynamic>, {});
    final v = ((r['platforms'] as Map)['ig'] as Map)['verdict'] as Map;
    expect((v['findings'] as List), isNotEmpty);
    expect(v['score'], inInclusiveRange(0, 100));
    final ig = (r['platforms'] as Map)['ig'] as Map;
    expect(((ig['content'] as Map)['classified'] as int), greaterThan(0));
    jsonEncode(r); // must be storable
  });

  test('youtube json parses, skips ads and removed videos', () {
    final r = ytFromJson('ytWatch', [
      {'title': 'Watched Cool video', 'titleUrl': 'https://www.youtube.com/watch?v=abcdefghijk', 'subtitles': [{'name': 'Chan'}], 'time': '2026-10-01T10:00:00.000Z'},
      {'title': 'Watched a video that has been removed', 'time': '2026-10-01T10:00:00.000Z'},
      {'title': 'Watched Ad', 'titleUrl': 'https://www.youtube.com/watch?v=zzzzzzzzzzz', 'details': [{'name': 'From Google Ads'}], 'time': '2026-10-01T10:00:00.000Z'},
    ]);
    expect(r.events.length, 1);
    expect(r.events.first['text'], 'Cool video');
    expect(r.events.first['by'], 'Chan');
    expect(r.skippedAds, 1);
  });

  test('a zip is read in the background; messages inside are ignored', () async {
    final dir = Directory.systemTemp.createTempSync('nl_imp');
    final arc = Archive()
      ..addFile(ArchiveFile.bytes('your_instagram_activity/likes/liked_posts.json', utf8.encode(jsonEncode({'likes_media_likes': likes(3, 5)}))))
      ..addFile(ArchiveFile.bytes('your_instagram_activity/messages/inbox/x/message_1.json', utf8.encode('{"secret": true}')));
    final zip = File('${dir.path}/export.zip')..writeAsBytesSync(ZipEncoder().encode(arc));
    final out = await readExports([zip.path]);
    expect(out['ignoredPrivate'], 1);
    expect(((out['events'] as Map)['ig'] as List).length, 15);
    dir.deleteSync(recursive: true);
  });
}

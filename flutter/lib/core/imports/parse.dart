import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

/// Import: reads Instagram "Download your information" and Google Takeout (YouTube) exports on the phone.
/// Only an allowlist of history files is ever opened; messages and personal details are skipped and never read.
/// Everything is turned into one event shape: {src, kind, act, t (epoch seconds), url, text, by}.

typedef Ev = Map<String, dynamic>;

final _ig = <(String, RegExp, String)>[
  ('igVideosWatched', RegExp(r'(^|/)videos_watched\.json$', caseSensitive: false), 'Reels watched'),
  ('igPostsViewed', RegExp(r'(^|/)posts_viewed\.json$', caseSensitive: false), 'Posts viewed'),
  ('igLikes', RegExp(r'(^|/)liked_posts\.json$', caseSensitive: false), 'Likes'),
  ('igSaved', RegExp(r'(^|/)saved_posts\.json$', caseSensitive: false), 'Saved'),
  ('igStories', RegExp(r'(^|/)stories_viewed\.json$', caseSensitive: false), 'Stories viewed'),
  ('igComments', RegExp(r'(^|/)(post_comments[^/]*|reels_comments[^/]*)\.json$', caseSensitive: false), 'Comments'),
  ('igFollowing', RegExp(r'(^|/)followers_and_following/following\.json$', caseSensitive: false), 'Accounts followed'),
  ('igSearchWords', RegExp(r'(^|/)word_or_phrase_searches\.json$', caseSensitive: false), 'Keyword searches'),
  ('igSearchRecent', RegExp(r'(^|/)recent_searches\.json$', caseSensitive: false), 'Recent searches'),
  ('igSearchProfiles', RegExp(r'(^|/)(profile_searches|account_searches)\.json$', caseSensitive: false), 'Profile searches'),
  ('igNotInterested', RegExp(r"(^|/)posts_you'?re_not_interested_in\.json$", caseSensitive: false), 'Marked not interested'),
  ('igSeeLess', RegExp(r'(^|/)see_less_topics\.json$', caseSensitive: false), 'Topics hidden'),
  ('igAds', RegExp(r'(^|/)ads_viewed\.json$', caseSensitive: false), 'Ads seen'),
];
final _yt = <(String, RegExp, String)>[
  ('ytWatch', RegExp(r'(^|/)watch-history\.(json|html)$', caseSensitive: false), 'Videos watched'),
  ('ytSearch', RegExp(r'(^|/)search-history\.(json|html)$', caseSensitive: false), 'Searches'),
  ('ytSubs', RegExp(r'(^|/)subscriptions/[^/]*\.csv$', caseSensitive: false), 'Subscriptions'),
  ('ytLiked', RegExp(r'(^|/)liked videos\.csv$', caseSensitive: false), 'Liked videos'),
];
final Map<String, String> importLabels = {for (final e in [..._ig, ..._yt]) e.$1: e.$3};
final _igHtml = RegExp(r'(videos_watched|liked_posts|posts_viewed|stories_viewed|saved_posts)\.html?$', caseSensitive: false);
final _private = RegExp(r'(^|/)(messages|inbox|message_requests|personal_information|security_and_login_information)/', caseSensitive: false);

String _norm(String n) => n.replaceAll('\\', '/');
String? categorize(String name) {
  final n = _norm(name);
  for (final e in [..._ig, ..._yt]) {
    if (e.$2.hasMatch(n)) return e.$1;
  }
  return null;
}

bool isPrivatePath(String name) => _private.hasMatch(_norm(name));

/// Instagram's JSON is UTF-8 that was mis-decoded as Latin-1; undo that when it looks like it.
String fixText(Object? v) {
  if (v is! String) return '';
  if (!RegExp('[Â-ô][\u0080-¿]').hasMatch(v)) return v;
  try {
    return utf8.decode(v.codeUnits.map((c) => c > 255 ? throw const FormatException() : c).toList());
  } catch (_) {
    return v;
  }
}

int _secs(Object? t) {
  final n = t is num ? t : 0;
  return n > 1e12 ? (n / 1000).round() : n.round();
}

Map<String, dynamic>? _map(Object? o) => o is Map ? o.cast<String, dynamic>() : null;

int _deepTs(Object? o, [int d = 0]) {
  if (o is! Map || d > 4) return 0;
  if (o['timestamp'] is num) return (o['timestamp'] as num).toInt();
  for (final v in o.values) {
    final r = _deepTs(v, d + 1);
    if (r != 0) return r;
  }
  return 0;
}

String _igKind(String url, String fallback) => RegExp(r'/(reel|reels|tv)/', caseSensitive: false).hasMatch(url)
    ? 'reel'
    : RegExp(r'/stories/', caseSensitive: false).hasMatch(url)
        ? 'story'
        : RegExp(r'/p/', caseSensitive: false).hasMatch(url)
            ? 'post'
            : fallback;

List<Map<String, dynamic>> _listOf(Object? j) {
  if (j is List) return j.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  if (j is Map) {
    for (final v in j.values) {
      if (v is List) return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
  }
  return [];
}

String _s(Object? o) => (o is String) ? o : '';

List<Ev> igEvents(String cat, Object? json) {
  final out = <Ev>[];
  for (final it in _listOf(json)) {
    final m = <String, Map<String, dynamic>>{};
    for (final lv in (it['label_values'] as List? ?? [])) {
      final mm = _map(lv);
      if (mm != null && mm['label'] is String) m[mm['label'] as String] = mm;
    }
    final smd = _map(it['string_map_data']) ?? {};
    final sldList = it['string_list_data'] as List? ?? [];
    final sld = sldList.isNotEmpty ? (_map(sldList.first) ?? {}) : <String, dynamic>{};
    final update = m['Update time']?['timestamp_value'];
    final t = _secs(it['timestamp'] ?? update ?? sld['timestamp'] ?? _deepTs(smd));
    final urlO = m['URL'];
    final url = _s(urlO?['href']).isNotEmpty ? _s(urlO?['href']) : _s(urlO?['value']).isNotEmpty ? _s(urlO?['value']) : _s(sld['href']).isNotEmpty ? _s(sld['href']) : _s(_map(smd['Saved on'])?['href']);
    final text = fixText(_first([m['Caption']?['value'], m['Search query']?['value'], _map(smd['Comment'])?['value'], _map(smd['Search'])?['value'], sld['value']])).trim();
    final by = fixText(_first([m['Title']?['value'], _map(smd['Media Owner'])?['value'], it['title']])).trim().replaceFirst(RegExp(r'^@'), '');
    final ev = <String, dynamic>{'src': 'ig', 't': t, 'url': url, 'text': text, 'by': by};
    switch (cat) {
      case 'igVideosWatched': ev..['kind'] = _igKind(url, 'reel')..['act'] = 'view';
      case 'igPostsViewed': ev..['kind'] = _igKind(url, 'post')..['act'] = 'view';
      case 'igLikes': ev..['kind'] = _igKind(url, 'post')..['act'] = 'like';
      case 'igSaved': ev..['kind'] = _igKind(url, 'post')..['act'] = 'save';
      case 'igStories': ev..['kind'] = 'story'..['act'] = 'view';
      case 'igComments': ev..['kind'] = 'comment'..['act'] = 'comment';
      case 'igFollowing': ev..['kind'] = 'profile'..['act'] = 'follow'..['text'] = '';
      case 'igSearchWords' || 'igSearchRecent': ev..['kind'] = 'search'..['act'] = 'search';
      case 'igSearchProfiles': ev..['kind'] = 'search'..['act'] = 'search'..['text'] = by;
      case 'igNotInterested': ev..['kind'] = 'post'..['act'] = 'hide'..['text'] = '';
      case 'igSeeLess':
        final labs = (it['label_values'] as List? ?? []).map((l) => _s(_map(l)?['label'])).where((l) => l.isNotEmpty);
        ev..['kind'] = 'profile'..['act'] = 'hide'..['text'] = fixText(labs.isEmpty ? '' : labs.first)..['t'] = _secs(it['timestamp']);
      case 'igAds': ev..['kind'] = 'post'..['act'] = 'ad'..['text'] = '';
      default: continue;
    }
    if (ev['t'] != 0 || cat == 'igSeeLess') out.add(ev);
  }
  return out;
}

Object? _first(List<Object?> xs) {
  for (final x in xs) {
    if (x is String && x.isNotEmpty) return x;
  }
  return '';
}

final _watchPrefix = RegExp(r'^(watched|viewed|listened to|visto|vu|angesehen|assistido|guardado)\s+', caseSensitive: false);

({List<Ev> events, int skippedAds}) ytFromJson(String cat, Object? json) {
  final out = <Ev>[];
  var ads = 0;
  for (final raw in json is List ? json : const []) {
    final it = _map(raw);
    if (it == null || it['time'] == null) continue;
    final dt = DateTime.tryParse(_s(it['time']));
    if (dt == null) continue;
    final t = (dt.millisecondsSinceEpoch / 1000).round();
    if ((it['details'] as List? ?? []).any((d) => RegExp('google ads', caseSensitive: false).hasMatch(_s(_map(d)?['name'])))) {
      ads++;
      continue;
    }
    final url = _s(it['titleUrl']);
    var title = fixText(it['title']);
    if (cat == 'ytWatch') {
      if (url.isEmpty) continue; // "Watched a video that has been removed"
      title = title.replaceFirst(_watchPrefix, '');
      final music = (it['products'] as List? ?? []).any((p) => RegExp('music', caseSensitive: false).hasMatch(_s(p))) || url.contains('music.youtube');
      final subs = it['subtitles'] as List? ?? [];
      out.add({'src': 'yt', 'kind': music ? 'music' : url.contains('/shorts/') ? 'short' : 'video', 'act': 'view', 't': t, 'url': url, 'text': title, 'by': fixText(subs.isNotEmpty ? (_map(subs.first) ?? const {})['name'] : '')});
    } else {
      out.add({'src': 'yt', 'kind': 'search', 'act': 'search', 't': t, 'url': url, 'text': title.replaceFirst(RegExp(r'^(searched for|searched|buscaste|recherché)\s+', caseSensitive: false), ''), 'by': ''});
    }
  }
  return (events: out, skippedAds: ads);
}

List<List<String>> _csvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cur = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        cur.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == ',') {
      row.add(cur.toString());
      cur.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cur.toString());
      cur.clear();
      if (row.length > 1 || row[0].isNotEmpty) rows.add(row);
      row = [];
    } else {
      cur.write(c);
    }
  }
  if (cur.isNotEmpty || row.isNotEmpty) {
    row.add(cur.toString());
    rows.add(row);
  }
  return rows;
}

List<Ev> ytFromCsv(String cat, String text) {
  final rows = _csvRows(text);
  if (rows.isEmpty) return [];
  final head = rows.first.map((h) => h.replaceFirst('﻿', '').trim().toLowerCase()).toList();
  String col(List<String> r, String name) {
    final i = head.indexOf(name);
    return i >= 0 && i < r.length ? r[i].trim() : '';
  }

  final body = rows.skip(1);
  if (cat == 'ytSubs') {
    return [for (final r in body) {'src': 'yt', 'kind': 'profile', 'act': 'sub', 't': 0, 'url': col(r, 'channel url'), 'text': col(r, 'channel title'), 'by': col(r, 'channel title')}];
  }
  final out = <Ev>[];
  for (final r in body) {
    final id = col(r, 'video id');
    if (id.isEmpty) continue;
    final dt = DateTime.tryParse(col(r, 'playlist video creation timestamp'));
    out.add({'src': 'yt', 'kind': 'video', 'act': 'like', 't': dt == null ? 0 : (dt.millisecondsSinceEpoch / 1000).round(), 'url': 'https://www.youtube.com/watch?v=$id', 'text': '', 'by': ''});
  }
  return out;
}

class _Source {
  _Source(this.name, this.read);
  final String name;
  final String Function() read;
}

/// Reads the picked files (zips, loose json/csv) and returns everything found. Runs in a background isolate.
Future<Map<String, dynamic>> readExports(List<String> paths) => Isolate.run(() => _readExports(paths));

Map<String, dynamic> _readExports(List<String> paths) {
  final sources = <_Source>[];
  var ignoredPrivate = 0, totalEntries = 0, igHtml = 0;
  final handles = <InputFileStream>[];
  for (final p in paths) {
    final lower = p.toLowerCase();
    if (lower.endsWith('.zip')) {
      final input = InputFileStream(p);
      handles.add(input);
      Archive z;
      try {
        z = ZipDecoder().decodeStream(input);
      } catch (_) {
        continue;
      }
      for (final e in z.files) {
        if (!e.isFile) continue;
        totalEntries++;
        final name = _norm(e.name);
        if (isPrivatePath(name)) {
          ignoredPrivate++; // never even listed as a candidate
          continue;
        }
        if (categorize(name) != null) {
          sources.add(_Source(name, () => utf8.decode(e.content as List<int>, allowMalformed: true)));
        } else if (_igHtml.hasMatch(name)) {
          igHtml++;
        }
      }
    } else {
      totalEntries++;
      final name = _norm(p);
      if (isPrivatePath(name)) {
        ignoredPrivate++;
        continue;
      }
      if (categorize(name) != null) {
        sources.add(_Source(name, () => File(p).readAsStringSync()));
      } else if (_igHtml.hasMatch(name)) {
        igHtml++;
      }
    }
  }

  final events = <String, List<Ev>>{'ig': [], 'yt': []};
  final ranges = <String, Map<String, int>>{};
  final problems = <String>[];
  var adsSkipped = 0, htmlYt = 0;
  for (final s in sources) {
    final cat = categorize(s.name)!;
    try {
      final text = s.read();
      List<Ev> evs;
      if (cat.startsWith('ig')) {
        evs = igEvents(cat, jsonDecode(text));
      } else if (s.name.toLowerCase().endsWith('.csv')) {
        evs = ytFromCsv(cat, text);
      } else if (s.name.toLowerCase().endsWith('.json')) {
        final r = ytFromJson(cat, jsonDecode(text));
        evs = r.events;
        adsSkipped += r.skippedAds;
      } else {
        htmlYt++;
        evs = [];
      }
      events[cat.startsWith('ig') ? 'ig' : 'yt']!.addAll(evs);
      final r = ranges.putIfAbsent(cat, () => {'n': 0, 'from': 0, 'to': 0});
      r['n'] = r['n']! + evs.length;
      final ts = evs.map((e) => e['t'] as int).where((t) => t > 0).toList();
      if (ts.isNotEmpty) {
        final a = ts.reduce((x, y) => x < y ? x : y), b = ts.reduce((x, y) => x > y ? x : y);
        r['from'] = r['from'] == 0 ? a : (r['from']! < a ? r['from']! : a);
        r['to'] = r['to']! > b ? r['to']! : b;
      }
    } catch (e) {
      problems.add('${s.name.split('/').last}: couldn\'t be read');
    }
  }
  if (htmlYt > 0) problems.add('Some YouTube files are in HTML format. Export from Google Takeout again and choose JSON as the history format.');
  for (final h in handles) {
    try {
      h.closeSync();
    } catch (_) {}
  }
  return {'events': events, 'ranges': ranges, 'problems': problems, 'ignoredPrivate': ignoredPrivate, 'totalEntries': totalEntries, 'igHtml': igHtml, 'files': paths.length, 'sources': sources.length, 'adsSkipped': adsSkipped};
}

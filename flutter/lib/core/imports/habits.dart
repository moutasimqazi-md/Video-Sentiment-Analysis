import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'parse.dart';

/// Habits analysis + judgement over imported Instagram / YouTube history (port of the website's rules, same thresholds).
/// Every export covers a different window, so each metric comes from one named series and each finding states its basis and confidence.

typedef Json = Map<String, dynamic>;

const habitRules = <Json>[
  {'platform': 'Instagram', 'what': 'Likes on a typical active day', 'bands': '< 30 fine · 30–60 · 60–120 · > 120'},
  {'platform': 'Instagram', 'what': 'Stories viewed on a typical day', 'bands': '< 50 fine · 50–150 · 150–300 · > 300'},
  {'platform': 'YouTube', 'what': 'Videos watched on a typical active day', 'bands': '< 15 fine · 15–40 · 40–80 · > 80'},
  {'platform': 'Both', 'what': 'Share of activity between midnight and 5am', 'bands': '< 5% fine · 5–10% · 10–15% · 15–25% · 25–35% · > 35%'},
  {'platform': 'Both', 'what': 'Unusually heavy days (3× your normal, per 30 days)', 'bands': '< 0.5 fine · 0.5–2 · 2–5 · > 5'},
  {'platform': 'Instagram', 'what': 'Longest unbroken run (a gap of 10 minutes ends it)', 'bands': '< 30 min fine · 30–60 · 60–120 · > 120'},
  {'platform': 'YouTube', 'what': 'Longest unbroken run (a gap of 30 minutes ends it)', 'bands': '< 60 min fine · 60–120 · 120–240 · > 240'},
  {'platform': 'YouTube', 'what': 'Share of videos from your 10 most-watched channels', 'bands': '< 50% fine · 50–70% · > 70%'},
  {'platform': 'Both', 'what': 'Last 30 days vs the 30 before', 'bands': '< +40% fine · +40–100% · > +100%'},
  {'platform': 'Both', 'what': 'Share of captions / titles with a heavy emotional tone', 'bands': '< 10% fine · 10–20% · 20–30% · > 30%'},
];

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
String hourLabel(int h) => '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'am' : 'pm'}';
String _p2(int n) => n.toString().padLeft(2, '0');
String _dayKey(DateTime d) => '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
double _median(List<num> a) {
  if (a.isEmpty) return 0;
  final s = [...a]..sort();
  final m = s.length >> 1;
  return s.length.isOdd ? s[m].toDouble() : (s[m - 1] + s[m]) / 2;
}

int _pct(double x) => (x * 100).round();
String _nf(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

String _friendly(String k) {
  final p = k.split('-').map(int.parse).toList();
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[p[1] - 1]} ${p[2]}, ${p[0]}';
}

String _mins(double m) => m < 1 ? 'under a minute' : '${m.round()} min';
String _conf(int n, int days) => n >= 500 && days >= 60 ? 'high' : n >= 100 && days >= 14 ? 'medium' : 'low';

Json? _stats(List<Ev> events, {required int gapSec, required int minBinge}) {
  final ev = events.where((e) => (e['t'] as int) > 0).toList()..sort((a, b) => (a['t'] as int).compareTo(b['t'] as int));
  if (ev.isEmpty) return null;
  final from = ev.first['t'] as int, to = ev.last['t'] as int;
  final days = math.max(1, ((to - from) / 86400).ceil() + 1);
  final byHour = List.filled(24, 0), byWeekday = List.filled(7, 0);
  final daily = <String, int>{}, monthly = <String, int>{};
  for (final e in ev) {
    final d = DateTime.fromMillisecondsSinceEpoch((e['t'] as int) * 1000);
    byHour[d.hour]++;
    byWeekday[d.weekday - 1]++;
    final dk = _dayKey(d);
    daily[dk] = (daily[dk] ?? 0) + 1;
    monthly[dk.substring(0, 7)] = (monthly[dk.substring(0, 7)] ?? 0) + 1;
  }
  final dayKeys = daily.keys.toList()..sort();
  final vals = dayKeys.map((k) => daily[k]!).toList();
  final med = _median(vals), threshold = math.max(minBinge.toDouble(), med * 3);
  final binge = dayKeys.where((k) => daily[k]! >= threshold).map((k) => {'date': k, 'n': daily[k]!}).toList()..sort((a, b) => (b['n'] as int).compareTo(a['n'] as int));
  final night = (byHour[0] + byHour[1] + byHour[2] + byHour[3] + byHour[4]) / ev.length;

  final sessions = <List<int>>[]; // [start, last, n]
  for (final e in ev) {
    final t = e['t'] as int;
    if (sessions.isEmpty || t - sessions.last[1] > gapSec) {
      sessions.add([t, t, 1]);
    } else {
      sessions.last[1] = t;
      sessions.last[2]++;
    }
  }
  double smin(List<int> s) => (s[1] - s[0]) / 60;
  List<int>? longest;
  for (final s in sessions) {
    if (longest == null || smin(s) > smin(longest)) longest = s;
  }

  Json? trend;
  if (days >= 60) {
    final a = ev.where((e) => (e['t'] as int) > to - 30 * 86400).length;
    final b = ev.where((e) => (e['t'] as int) <= to - 30 * 86400 && (e['t'] as int) > to - 60 * 86400).length;
    if (b >= 20) trend = {'last': a, 'prev': b, 'change': (a - b) / b};
  }
  final trimmed = {for (final k in dayKeys.skip(math.max(0, dayKeys.length - 200))) k: daily[k]!};
  final peakHour = byHour.indexOf(byHour.reduce(math.max)), peakWeekday = byWeekday.indexOf(byWeekday.reduce(math.max));
  return {
    'n': ev.length, 'from': from, 'to': to, 'days': days, 'activeDays': dayKeys.length, 'perActiveDay': med, 'meanPerActiveDay': ev.length / dayKeys.length,
    'maxDay': vals.reduce(math.max), 'byHour': byHour, 'byWeekday': byWeekday, 'daily': trimmed, 'monthly': monthly, 'nightShare': night, 'peakHour': peakHour, 'peakWeekday': peakWeekday,
    'binge': {'threshold': threshold, 'days': binge.take(8).toList(), 'count': binge.length},
    'sessions': {
      'count': sessions.length, 'medianMin': _median(sessions.map(smin).toList()), 'perActiveDay': sessions.length / dayKeys.length,
      'longest': longest == null ? null : {'min': smin(longest), 'n': longest[2], 'date': _dayKey(DateTime.fromMillisecondsSinceEpoch(longest[0] * 1000))},
    },
    'trend': trend,
  };
}

Map<String, int> _countBy(Iterable<Ev> arr, String Function(Ev) f) {
  final m = <String, int>{};
  for (final e in arr) {
    final k = f(e);
    m[k] = (m[k] ?? 0) + 1;
  }
  return m;
}

List<Json> _topTerms(Iterable<Ev> events, int n) {
  final m = <String, int>{};
  for (final e in events) {
    final k = (e['text'] as String).trim().toLowerCase();
    if (k.isNotEmpty) m[k] = (m[k] ?? 0) + 1;
  }
  final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return l.take(n).map((e) => {'q': e.key, 'n': e.value}).toList();
}

/* ---------------- caption / title themes ---------------- */
class _Themes {
  _Themes(Json lexicon) : _themes = (lexicon['themes'] as Map).cast<String, dynamic>(), heavy = {...(lexicon['heavyMoods'] as List).cast<String>()} {
    for (final entry in _themes.entries) {
      final th = (entry.value as Map).cast<String, dynamic>();
      for (final t in (th['tags'] as List).cast<String>()) {
        tagMap.putIfAbsent(t.toLowerCase(), () => []).add(entry.key);
      }
      for (var w in (th['words'] as List).cast<String>()) {
        w = w.toLowerCase();
        if (RegExp(r'\s').hasMatch(w)) {
          phrases.add((w, entry.key));
        } else {
          tokenMap.putIfAbsent(w, () => []).add(entry.key);
        }
      }
    }
  }
  final Map<String, dynamic> _themes;
  final Set<String> heavy;
  final tokenMap = <String, List<String>>{}, tagMap = <String, List<String>>{};
  final phrases = <(String, String)>[];

  ({String theme, String mood, double score})? classify(String text) {
    final t = text.toLowerCase();
    if (t.length < 3) return null;
    final scores = <String, double>{};
    void bump(String k, double w) => scores[k] = (scores[k] ?? 0) + w;
    for (final m in RegExp(r'#([\p{L}\p{N}_]+)', unicode: true).allMatches(t)) {
      final tag = m.group(1)!;
      final ks = tagMap[tag] ?? tokenMap[tag];
      if (ks != null) {
        for (final k in ks) {
          bump(k, tagMap.containsKey(tag) ? 2 : 1);
        }
      }
    }
    final seen = <String>{};
    for (final m in RegExp(r"[\p{L}\p{N}_']+", unicode: true).allMatches(t.replaceAll(RegExp(r'#[\p{L}\p{N}_]+', unicode: true), ' '))) {
      final w = m.group(0)!;
      if (!seen.add(w)) continue;
      final ks = tokenMap[w];
      if (ks != null) {
        for (final k in ks) {
          bump(k, 1);
        }
      }
    }
    for (final (ph, k) in phrases) {
      if (t.contains(ph)) bump(k, 1.5);
    }
    String? best;
    var b = 0.0;
    scores.forEach((k, v) {
      if (v > b) {
        b = v;
        best = k;
      }
    });
    if (best == null || b < 1) return null;
    return (theme: best!, mood: (_themes[best]['mood'] as String), score: b);
  }

  Json summarize(List<Ev> events) {
    final themes = <String, int>{}, moods = <String, int>{};
    final months = <String, List<int>>{};
    final flagged = <Json>[];
    var classified = 0, heavyN = 0;
    for (final e in events) {
      final c = classify(e['text'] as String);
      if (c == null) continue;
      classified++;
      themes[c.theme] = (themes[c.theme] ?? 0) + 1;
      moods[c.mood] = (moods[c.mood] ?? 0) + 1;
      final isHeavy = heavy.contains(c.mood);
      if (isHeavy) heavyN++;
      final t = e['t'] as int;
      if (t > 0) {
        final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
        final mk = '${d.year}-${_p2(d.month)}';
        final m = months.putIfAbsent(mk, () => [0, 0]);
        m[0]++;
        if (isHeavy) m[1]++;
      }
      if (isHeavy && c.score >= 2 && (e['url'] as String).isNotEmpty) {
        final txt = (e['text'] as String).replaceAll(RegExp(r'\s+'), ' ');
        flagged.add({'url': e['url'], 'text': txt.length > 140 ? txt.substring(0, 140) : txt, 't': t, 'src': e['src'], 'theme': c.theme, 'mood': c.mood, 'score': c.score});
      }
    }
    double pct(int n) => classified == 0 ? 0 : n / classified * 100;
    flagged.sort((a, b) => (b['t'] as int).compareTo(a['t'] as int));
    final top = themes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {
      'total': events.length, 'classified': classified, 'classifiedShare': events.isEmpty ? 0 : classified / events.length,
      'themes': top.take(10).map((e) => {'key': e.key, 'label': (_themes[e.key]['label'] as String), 'mood': (_themes[e.key]['mood'] as String), 'n': e.value, 'share': pct(e.value)}).toList(),
      'heavyShare': classified == 0 ? 0 : heavyN / classified, 'heavyN': heavyN,
      'flagged': flagged.take(12).toList(),
    };
  }
}

/* ---------------- judgement ---------------- */
Json _judge(String platform, Json P) {
  final f = <Json>[];
  var score = 100;
  void add(Json o) {
    score -= (o['penalty'] as int?) ?? 0;
    f.add(o);
  }

  String sev(int p, int hi, int mid) => p >= hi ? 'high' : p >= mid ? 'watch' : p > 0 ? 'info' : 'good';
  final S = (P['series'] as Map).cast<String, Json?>();
  String basis(Json s, String what) => '${_nf(s['n'] as int)} $what over ${s['days']} day${s['days'] == 1 ? '' : 's'}';

  if (platform == 'ig') {
    final L = S['likes'];
    if (L != null && (L['n'] as int) >= 30) {
      final m = (L['perActiveDay'] as double).round(), p = m < 30 ? 0 : m < 60 ? 5 : m < 120 ? 12 : 20;
      add({'id': 'ig-likes', 'severity': sev(p, 20, 12), 'title': p >= 12 ? 'Heavy liking' : p > 0 ? 'Fairly active liking' : 'Moderate liking', 'penalty': p, 'confidence': _conf(L['n'] as int, L['days'] as int), 'basis': basis(L, 'likes'),
        'text': 'Active on ${L['activeDays']} of ${L['days']} days. A typical active day has about $m likes (the busiest had ${L['maxDay']}).',
        'tip': p > 0 ? "Likes happen while scrolling, so this is a good proxy for time spent. A daily limit in Instagram's Time Management can help." : 'Nothing to change here.'});
    }
    final T = S['stories'];
    if (T != null && (T['n'] as int) >= 100) {
      final m = (T['perActiveDay'] as double).round(), p = m < 50 ? 0 : m < 150 ? 5 : m < 300 ? 12 : 18;
      add({'id': 'ig-stories', 'severity': sev(p, 18, 12), 'title': p >= 12 ? 'High story volume' : p > 0 ? 'Regular story viewing' : 'Light story viewing', 'penalty': p, 'confidence': _conf(T['n'] as int, T['days'] as int), 'basis': basis(T, 'stories viewed'),
        'text': 'About $m stories viewed on a typical day (peak ${T['maxDay']}). Stories autoplay one after another, so volume adds up quickly.',
        'tip': p > 0 ? "Muting or hiding accounts you don't care about shortens the story tray a lot." : ''});
    }
  }
  if (platform == 'yt') {
    final V = S['views'];
    if (V != null && (V['n'] as int) >= 30) {
      final m = (V['perActiveDay'] as double).round(), p = m < 15 ? 0 : m < 40 ? 5 : m < 80 ? 12 : 20;
      add({'id': 'yt-views', 'severity': sev(p, 20, 12), 'title': p >= 12 ? 'Frequent watching' : p > 0 ? 'Regular watching' : 'Light watching', 'penalty': p, 'confidence': _conf(V['n'] as int, V['days'] as int), 'basis': basis(V, 'videos watched'),
        'text': "Active on ${V['activeDays']} of ${V['days']} days, with about $m videos on a typical active day (busiest day ${V['maxDay']}). YouTube doesn't record watch time, so this counts videos.",
        'tip': p > 0 ? 'Use YouTube\'s "Remind me to take a break" and turn autoplay off.' : ''});
    }
  }
  // night-time: judge on the series with the most data
  final present = S.entries.where((e) => e.value != null).toList()..sort((a, b) => (b.value!['n'] as int).compareTo(a.value!['n'] as int));
  if (present.isNotEmpty && (present.first.value!['n'] as int) >= 100) {
    final main = present.first.value!, name = present.first.key;
    final ns = main['nightShare'] as double, p = ns < 0.05 ? 0 : ns < 0.1 ? 4 : ns < 0.15 ? 8 : ns < 0.25 ? 14 : ns < 0.35 ? 20 : 25;
    add({'id': 'night', 'severity': sev(p, 20, 8), 'title': p >= 8 ? 'Late-night activity' : p > 0 ? 'Some late-night activity' : 'Little late-night activity', 'penalty': p, 'confidence': _conf(main['n'] as int, main['days'] as int),
      'basis': basis(main, name == 'likes' ? 'likes' : name == 'stories' ? 'stories' : 'views'),
      'text': '${_pct(ns)}% of activity happens between midnight and 5am. The busiest hour is ${hourLabel(main['peakHour'] as int)}, and ${weekdayNames[main['peakWeekday'] as int]} is the busiest day.',
      'tip': p > 0 ? 'Set a wind-down time and use ${platform == 'ig' ? 'Sleep mode' : 'Bedtime reminders'} so scrolling stops before sleep.' : 'A healthy pattern for sleep.'});
  }
  // binge days
  final bs = S.values.whereType<Json>().where((v) => (v['days'] as int) >= 7 && (v['n'] as int) >= 40).toList();
  if (bs.isNotEmpty) {
    final tot = bs.fold<int>(0, (a, v) => a + ((v['binge'] as Map)['count'] as int)), days = bs.fold<int>(0, (a, v) => a + (v['days'] as int)), rate = tot * 30 / math.max(days, 1);
    final p = rate < 0.5 ? 0 : rate < 2 ? 5 : rate < 5 ? 10 : 15;
    final all = bs.expand((v) => ((v['binge'] as Map)['days'] as List).cast<Json>()).toList()..sort((a, b) => (b['n'] as int).compareTo(a['n'] as int));
    final top = all.isEmpty ? null : all.first;
    add({'id': 'binge', 'severity': sev(p, 15, 10), 'title': p >= 10 ? 'Unusually heavy days' : tot > 0 ? 'A few heavy days' : 'Steady days', 'penalty': p,
      'confidence': _conf(bs.fold<int>(0, (a, v) => a + (v['n'] as int)), bs.map((v) => v['days'] as int).reduce(math.max)), 'basis': '$tot day${tot == 1 ? '' : 's'} well above normal',
      'text': tot > 0 ? '$tot day${tot == 1 ? '' : 's'} were at least 3× a normal day${top != null ? ', the biggest on ${_friendly(top['date'] as String)} with ${_nf(top['n'] as int)} items' : ''}.' : 'No days stand out as much heavier than the rest.',
      'tip': tot > 0 ? 'Look at what happened on those days: a bad day, boredom, or waiting around. Naming the trigger makes it easier to plan around.' : ''});
  }
  // longest unbroken run
  final sv = S['views'];
  final lg = sv == null ? null : (sv['sessions'] as Map)['longest'] as Map?;
  if (sv != null && (sv['n'] as int) >= 40 && lg != null) {
    final m = lg['min'] as double, lim = platform == 'ig' ? [30, 60, 120] : [60, 120, 240], pts = platform == 'ig' ? [0, 4, 8, 12] : [0, 5, 10, 15];
    final p = m < lim[0] ? pts[0] : m < lim[1] ? pts[1] : m < lim[2] ? pts[2] : pts[3];
    add({'id': 'session', 'severity': sev(p, pts[3], pts[2]), 'title': p >= 8 ? 'Long unbroken sessions' : p > 0 ? 'Some long sessions' : 'Sessions stay short', 'penalty': p, 'confidence': _conf(sv['n'] as int, sv['days'] as int), 'basis': basis(sv, 'timestamped views'),
      'text': 'Longest unbroken run: about ${m.round()} minutes (${lg['n']} items) on ${_friendly(lg['date'] as String)}. The median of ${_nf((sv['sessions'] as Map)['count'] as int)} sessions is ${_mins((sv['sessions'] as Map)['medianMin'] as double)}.',
      'tip': p > 0 ? 'A short pause between sessions breaks the autoplay loop.' : ''});
  }
  // variety (YouTube has channel names)
  final cr = P['creators'] as Map?;
  if (platform == 'yt' && cr != null && (cr['total'] as int) >= 100) {
    final s = cr['top10Share'] as double, p = s > 0.7 ? 10 : s > 0.5 ? 5 : 0;
    add({'id': 'variety', 'severity': p > 0 ? 'watch' : 'good', 'title': p > 0 ? 'Narrow viewing' : 'Varied viewing', 'penalty': p, 'confidence': _conf(cr['total'] as int, S['views'] != null ? S['views']!['days'] as int : 1),
      'basis': '${_nf(cr['total'] as int)} videos from ${_nf(cr['unique'] as int)} channels',
      'text': 'Your 10 most-watched channels make up ${_pct(s)}% of what you watch, out of ${_nf(cr['unique'] as int)} channels in total.',
      'tip': p > 0 ? 'A few channels dominating can narrow what you see. Try a couple of new topics.' : 'A varied mix is a healthier one.'});
  }
  // trend on the longest series
  final trs = S.values.whereType<Json>().where((v) => v['trend'] != null).toList()..sort((a, b) => (b['n'] as int).compareTo(a['n'] as int));
  if (trs.isNotEmpty) {
    final tr = trs.first, tt = tr['trend'] as Map, c = tt['change'] as double, p = c > 1 ? 10 : c > 0.4 ? 5 : 0;
    add({'id': 'trend', 'severity': c > 0.4 ? 'watch' : c < -0.25 ? 'good' : 'info', 'title': c > 0.4 ? 'Usage is rising' : c < -0.25 ? 'Usage is falling' : 'Usage is steady', 'penalty': p, 'confidence': _conf(tr['n'] as int, tr['days'] as int), 'basis': basis(tr, 'events'),
      'text': '${_nf(tt['last'] as int)} in the last 30 days versus ${_nf(tt['prev'] as int)} in the 30 days before (${c >= 0 ? '+' : ''}${_pct(c)}%).',
      'tip': c > 0.4 ? 'A sudden jump is worth noticing. What changed: stress, boredom, a new habit?' : ''});
  }
  // content tone
  final C = P['content'] as Map?;
  if (C != null && (C['classified'] as int) >= 100) {
    final h = (C['heavyShare'] as num).toDouble(), p = h < 0.1 ? 0 : h < 0.2 ? 5 : h < 0.3 ? 10 : 15;
    final themes = (C['themes'] as List).take(3).map((t) => (t as Map)['label']).join(', ');
    add({'id': 'tone', 'severity': sev(p, 15, 10), 'title': p >= 10 ? 'Heavier-toned content' : p > 0 ? 'Somewhat heavier-toned content' : 'Mostly light-toned content', 'penalty': p, 'confidence': (C['classified'] as int) >= 500 ? 'medium' : 'low',
      'basis': '${_nf(C['classified'] as int)} of ${_nf(C['total'] as int)} captions/titles recognised',
      'text': '${_pct(h)}% of recognised content carries a heavier emotional tone (sadness, anger, loneliness, stress). Biggest themes: ${themes.isEmpty ? 'none recognised' : themes}.',
      'tip': p > 0 ? "Heavy content isn't bad in itself, but a feed that is mostly heavy can weigh on mood. Add some lighter accounts and topics." : ''});
  }
  score = score.clamp(0, 100);
  final enough = f.isNotEmpty;
  final label = !enough ? 'Not enough data' : score >= 80 ? 'Balanced' : score >= 60 ? 'Mostly healthy, a few things to watch' : score >= 40 ? 'Several habits worth a look' : 'Needs attention';
  final level = !enough ? 'info' : score >= 80 ? 'good' : score >= 60 ? 'info' : score >= 40 ? 'watch' : 'high';
  final flagged = f.where((x) => x['severity'] == 'watch' || x['severity'] == 'high').toList();
  return {'score': score, 'label': label, 'level': level, 'findings': f,
    'summary': !enough ? 'Not enough history in this export to judge.' : flagged.isNotEmpty ? 'Worth a look: ${flagged.map((x) => (x['title'] as String).toLowerCase()).join(', ')}.' : 'No habits stand out as a concern.'};
}

Json _platformReport(String platform, List<Ev> events, _Themes themes) {
  final P = <String, dynamic>{'src': platform, 'series': <String, Json?>{}};
  final series = P['series'] as Map<String, Json?>;
  Iterable<Ev> where(bool Function(Ev) f) => events.where(f);
  if (platform == 'ig') {
    series['likes'] = _stats(where((e) => e['act'] == 'like').toList(), gapSec: 600, minBinge: 60);
    series['stories'] = _stats(where((e) => e['kind'] == 'story' && e['act'] == 'view').toList(), gapSec: 600, minBinge: 300);
    series['views'] = _stats(where((e) => e['act'] == 'view' && e['kind'] != 'story').toList(), gapSec: 600, minBinge: 60);
    P['mix'] = {'likes': _countBy(where((e) => e['act'] == 'like'), (e) => e['kind'] as String), 'views': _countBy(where((e) => e['act'] == 'view' && e['kind'] != 'story'), (e) => e['kind'] as String)};
    P['searches'] = {'total': where((e) => e['act'] == 'search').length, 'top': _topTerms(where((e) => e['act'] == 'search'), 8)};
    P['controls'] = {
      'notInterested': where((e) => e['act'] == 'hide' && e['kind'] == 'post').length,
      'topicsHidden': where((e) => e['act'] == 'hide' && e['kind'] == 'profile').map((e) => e['text'] as String).where((t) => t.isNotEmpty).take(12).toList(),
      'ads': where((e) => e['act'] == 'ad').length,
    };
    P['social'] = {'following': where((e) => e['act'] == 'follow').length, 'saved': where((e) => e['act'] == 'save').length, 'comments': where((e) => e['act'] == 'comment').length};
    P['content'] = themes.summarize(where((e) => const ['like', 'save', 'view'].contains(e['act']) && (e['text'] as String).isNotEmpty).toList());
  } else {
    final views = where((e) => e['act'] == 'view' && e['kind'] != 'music').toList();
    series['views'] = _stats(views, gapSec: 1800, minBinge: 60);
    final cnt = <String, int>{};
    for (final e in views) {
      final by = e['by'] as String;
      if (by.isNotEmpty) cnt[by] = (cnt[by] ?? 0) + 1;
    }
    final ranked = cnt.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = ranked.fold<int>(0, (a, b) => a + b.value);
    P['creators'] = {
      'total': views.length, 'withChannel': total, 'unique': ranked.length, 'top': ranked.take(12).map((e) => {'name': e.key, 'n': e.value}).toList(),
      'top10Share': total == 0 ? 0.0 : ranked.take(10).fold<int>(0, (a, b) => a + b.value) / total,
    };
    P['mix'] = {'kinds': _countBy(where((e) => e['act'] == 'view'), (e) => e['kind'] == 'video' && RegExp(r'#shorts?\b', caseSensitive: false).hasMatch(e['text'] as String) ? 'short' : e['kind'] as String)};
    P['searches'] = {'total': where((e) => e['act'] == 'search').length, 'top': _topTerms(where((e) => e['act'] == 'search'), 8)};
    P['social'] = {'subscriptions': where((e) => e['act'] == 'sub').length, 'liked': where((e) => e['act'] == 'like').length};
    P['content'] = themes.summarize(views.map((e) => {...e, 'text': '${e['text']} ${e['by']}'}).toList());
  }
  P['verdict'] = _judge(platform, P);
  return P;
}

/// A compact snapshot of an earlier report, so the next import can say what changed.
Json snapshotOf(Json r) {
  final out = <String, dynamic>{'createdAt': r['createdAt'], 'overall': (r['overall'] as Map?)?['score'], 'platforms': <String, dynamic>{}};
  for (final e in ((r['platforms'] as Map?) ?? {}).entries) {
    final P = (e.value as Map).cast<String, dynamic>();
    final ss = (P['series'] as Map).values.whereType<Map>().toList()..sort((a, b) => (b['n'] as int).compareTo(a['n'] as int));
    final s = ss.isEmpty ? null : ss.first;
    out['platforms'][e.key] = {'score': (P['verdict'] as Map)['score'], 'night': s?['nightShare'], 'perDay': s?['perActiveDay'], 'n': s?['n'] ?? 0};
  }
  return out;
}

/// One report for one platform; Instagram and YouTube are never combined.
Json analyzePlatform(String platform, List<Ev> events, Json lexicon, Json meta) {
  final r = <String, dynamic>{'version': 2, 'createdAt': DateTime.now().millisecondsSinceEpoch, 'meta': meta, 'platforms': {platform: _platformReport(platform, events, _Themes(lexicon))}};
  final v = ((r['platforms'] as Map)[platform] as Map)['verdict'] as Map;
  final enough = (v['findings'] as List).isNotEmpty;
  r['overall'] = enough
      ? {'score': v['score'], 'label': v['label'], 'level': v['level'], 'summary': v['summary']}
      : {'score': null, 'label': 'Not enough data', 'level': 'info', 'summary': "These files don't contain enough history to judge habits."};
  return r;
}

/// Builds the report in a background isolate (thousands of items).
Future<Json> buildReport(String platform, List<Ev> events, String lexiconJson, Json meta) =>
    Isolate.run(() => analyzePlatform(platform, events, (jsonDecode(lexiconJson) as Map).cast<String, dynamic>(), meta));

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/imports/habits.dart';
import '../../core/imports/import_store.dart';
import '../../core/stores.dart';
import '../widgets/common.dart';
import 'import_screen.dart';

Color _levelColor(BuildContext c, String level) => switch (level) {
      'good' => const Color(0xFF137350),
      'watch' => const Color(0xFF8F5A05),
      'high' => Theme.of(c).colorScheme.primary,
      _ => const Color(0xFF4A7CF0),
    };

String _date(Object? ms) => DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch((ms as num).toInt()));
String _n(num v) => NumberFormat.decimalPattern().format(v.round());

/// A saved habits report for one profile and one platform.
class HabitsReportScreen extends StatelessWidget {
  const HabitsReportScreen({super.key, required this.profile, required this.src});
  final String profile, src;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final store = context.watch<ImportStore>();
    final profiles = context.watch<ProfilesStore>();
    final report = store.get(profile, src);
    final plat = ImportStore.platformNames[src]!;
    final who = profiles.nameOf(profile);
    final possessive = who == 'Me' ? 'Your' : "$who's";

    if (report == null) {
      return Scaffold(appBar: AppBar(title: Text('$plat habits')), body: EmptyState(icon: Icons.insights_outlined, title: 'No report yet', text: 'Import your $plat history to see this report.', action: FilledButton(onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ImportScreen(profile: profile))), child: const Text('Import now'))));
    }

    final overall = (report['overall'] as Map).cast<String, dynamic>();
    final P = ((report['platforms'] as Map)[src] as Map).cast<String, dynamic>();
    final verdict = (P['verdict'] as Map).cast<String, dynamic>();
    final findings = (verdict['findings'] as List).cast<Map>();
    final series = (P['series'] as Map).cast<String, dynamic>();
    final prev = report['prev'] as Map?;
    final score = overall['score'] as int?;
    final level = overall['level'] as String;
    final others = store.sourcesFor(profile).where((s) => s != src).toList();

    Widget card(String title, Widget child, {String? sub}) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: NlCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))),
            const SizedBox(height: 12),
            child,
          ])),
        );

    return Scaffold(
      appBar: AppBar(title: Text('$possessive $plat habits'), actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'update') {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ImportScreen(profile: profile)));
            } else if (v == 'delete') {
              final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Delete this report?'), content: const Text('The report is removed from this phone.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]));
              if (ok == true) {
                await store.remove(profile, src);
                if (context.mounted) Navigator.of(context).pop();
              }
            }
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'update', child: Text('Import newer data')), PopupMenuItem(value: 'delete', child: Text('Delete report'))],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        Text('Imported ${_date(report['createdAt'])}. Everything here was calculated on this phone.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        NlCard(child: Row(children: [
          Ring(fraction: (score ?? 0) / 100, center: score?.toString() ?? '–', sub: 'of 100', size: 104, color: _levelColor(context, level)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(overall['label'] as String, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(overall['summary'] as String, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            if (prev != null && prev['overall'] != null && score != null) ...[
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final d = score - (prev['overall'] as num).round();
                return Pill(d == 0 ? 'No change since ${_date(prev['createdAt'])}' : '${d > 0 ? '▲' : '▼'} ${d.abs()} points since ${_date(prev['createdAt'])}', tone: d > 0 ? Tone.green : d < 0 ? Tone.amber : Tone.neutral);
              }),
            ],
          ])),
        ])),
        const SizedBox(height: 14),
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HabitsReportScreen(profile: profile, src: others.first))), icon: const Icon(Icons.swap_horiz), label: Text('Open the separate ${ImportStore.platformNames[others.first]} report'))),
          ),
        if (findings.isEmpty)
          card('Not enough to judge', Text('These files have too little history for a verdict. For Instagram include Likes, Stories and Ads information; for YouTube include History; for TikTok request all data; for Facebook include Likes and reactions, Search history and watch activity (JSON).', style: t.textTheme.bodyMedium))
        else
          for (final f in findings.cast<Map<String, dynamic>>()) _Finding(f: f),
        const SizedBox(height: 4),
        ..._numbers(context, series, card),
        ..._charts(context, series, card),
        ..._themes(context, P, card),
        ..._extras(context, P, card),
        card('How the score works', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Every finding states what it is based on and how confident it is. Starting from 100, points come off when a habit crosses these limits.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          for (final r in habitRules.where((r) => r['platform'] == plat || r['platform'] == 'Both'))
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['what']!, style: const TextStyle(fontWeight: FontWeight.w700)), Text(r['bands']!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))])),
        ])),
        Text('A habits report is a guide, not a diagnosis.', textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }

  static const _seriesNames = {'likes': 'Likes', 'stories': 'Stories viewed', 'views': 'Views'};

  List<Widget> _numbers(BuildContext context, Map<String, dynamic> series, Widget Function(String, Widget, {String? sub}) card) {
    final t = Theme.of(context);
    final rows = [for (final e in series.entries) if (e.value != null) MapEntry(e.key, (e.value as Map).cast<String, dynamic>())];
    if (rows.isEmpty) return [];
    return [
      card('Your numbers', Column(children: [
        for (final e in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_seriesNames[e.key] ?? e.key, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _Stat(_n(e.value['n'] as num), 'items'),
                _Stat('${e.value['activeDays']} of ${e.value['days']}', 'active days'),
                _Stat(_n(e.value['perActiveDay'] as num), 'typical day'),
                _Stat('${((e.value['nightShare'] as num) * 100).round()}%', 'after midnight'),
                _Stat(hourLabel(e.value['peakHour'] as int), 'busiest hour'),
              ]),
              const SizedBox(height: 4),
              Text('${DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch((e.value['from'] as int) * 1000))} to ${DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch((e.value['to'] as int) * 1000))}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
      ])),
    ];
  }

  List<Widget> _charts(BuildContext context, Map<String, dynamic> series, Widget Function(String, Widget, {String? sub}) card) {
    final ranked = [for (final v in series.values) if (v != null) (v as Map).cast<String, dynamic>()]..sort((a, b) => (b['n'] as int).compareTo(a['n'] as int));
    if (ranked.isEmpty) return [];
    final main = ranked.first;
    final hours = (main['byHour'] as List).cast<int>(), wd = (main['byWeekday'] as List).cast<int>();
    return [
      card('When it happens', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Bars(values: hours, labels: [for (var h = 0; h < 24; h++) h % 6 == 0 ? hourLabel(h) : ''], labelsFull: [for (var h = 0; h < 24; h++) hourLabel(h)], height: 96, highlight: const {0, 1, 2, 3, 4}),
        const SizedBox(height: 14),
        _Bars(values: wd, labels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], labelsFull: weekdayNames, height: 80),
      ]), sub: 'Hour of day (late-night hours highlighted) and day of the week'),
    ];
  }

  List<Widget> _themes(BuildContext context, Map<String, dynamic> P, Widget Function(String, Widget, {String? sub}) card) {
    final t = Theme.of(context);
    final C = P['content'] as Map?;
    if (C == null || (C['classified'] as int) == 0) return [];
    final themes = (C['themes'] as List).cast<Map>();
    final flagged = (C['flagged'] as List).cast<Map>();
    return [
      card('What the content is about', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final th in themes.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(th['label'] as String, style: const TextStyle(fontWeight: FontWeight.w700))), Text('${(th['share'] as num).round()}%')]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: ((th['share'] as num) / 100).clamp(0, 1).toDouble(), minHeight: 8, backgroundColor: t.colorScheme.surfaceContainerHighest)),
            ]),
          ),
        Text('A keyword estimate from captions and titles, not a look at the videos themselves. ${(C['classified'] as int)} of ${(C['total'] as int)} were recognised.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ])),
      if (flagged.isNotEmpty)
        card('Heavier-toned items', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final f in flagged.take(6))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(f['text'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${f['theme']} · ${DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch((f['t'] as int) * 1000))}'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => launchUrl(Uri.parse(f['url'] as String), mode: LaunchMode.externalApplication),
            ),
        ]), sub: 'Tap to open the post'),
    ];
  }

  List<Widget> _extras(BuildContext context, Map<String, dynamic> P, Widget Function(String, Widget, {String? sub}) card) {
    final t = Theme.of(context);
    final out = <Widget>[];
    final cr = P['creators'] as Map?;
    if (cr != null && (cr['top'] as List).isNotEmpty) {
      out.add(card('Most-watched channels', Column(children: [
        for (final c in (cr['top'] as List).cast<Map>().take(8)) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Expanded(child: Text(c['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis)), Text('${c['n']}', style: const TextStyle(fontWeight: FontWeight.w700))])),
      ])));
    }
    final se = P['searches'] as Map?;
    if (se != null && (se['top'] as List).isNotEmpty) {
      out.add(card('Top searches', Wrap(spacing: 8, runSpacing: 8, children: [for (final q in (se['top'] as List).cast<Map>()) Pill('${q['q']} · ${q['n']}')]), sub: '${_n(se['total'] as num)} searches in total'));
    }
    final co = P['controls'] as Map?;
    if (co != null && ((co['notInterested'] as int) > 0 || (co['topicsHidden'] as List).isNotEmpty)) {
      out.add(card('Feed controls used', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${co['notInterested']} posts marked "not interested".', style: t.textTheme.bodyMedium),
        if ((co['topicsHidden'] as List).isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: [for (final x in (co['topicsHidden'] as List)) Pill('$x')])],
      ])));
    }
    return out;
  }
}

class _Finding extends StatelessWidget {
  const _Finding({required this.f});
  final Map<String, dynamic> f;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sev = f['severity'] as String;
    final icon = switch (sev) { 'good' => Icons.check_circle_outline, 'info' => Icons.visibility_outlined, _ => Icons.error_outline };
    final color = _levelColor(context, sev);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NlCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f['title'] as String, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(f['text'] as String, style: t.textTheme.bodyMedium),
          if ((f['tip'] as String).isNotEmpty) ...[const SizedBox(height: 6), Text(f['tip'] as String, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w600))],
          const SizedBox(height: 6),
          Text('Based on ${f['basis']} · ${f['confidence']} confidence', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ])),
      ])),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, required this.height, this.highlight = const {}, this.labelsFull = const []});
  final List<int> values;
  final List<String> labels;
  final List<String> labelsFull; // spoken names for the bars
  final double height;
  final Set<int> highlight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final max = values.fold<int>(1, (a, b) => b > a ? b : a);
    final peak = values.indexOf(max);
    return Semantics(
      label: 'Bar chart. Highest: ${labelsFull.isNotEmpty ? labelsFull[peak] : peak}, $max items.',
      child: ExcludeSemantics(child: Column(children: [
      SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: Container(height: (values[i] / max * height).clamp(2, height).toDouble(), decoration: BoxDecoration(color: highlight.contains(i) ? t.colorScheme.primary : const Color(0xFF4A7CF0).withValues(alpha: 0.75), borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))))),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [for (final l in labels) Expanded(child: Text(l, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.visible, softWrap: false, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant, fontSize: 9)))]),
    ])),
    );
  }
}

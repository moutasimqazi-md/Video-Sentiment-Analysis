import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/moods.dart';
import '../../core/stores.dart';
import '../../core/wellbeing.dart';
import '../widgets/common.dart';

void openResult(BuildContext context, HistoryEntry entry) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultsScreen(entry: entry)));

/// Opens an analysis that lives on the server only, e.g. an item found by a Feed check or named in an alert.
void openRemoteResult(BuildContext context, String jobId, {String? title}) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RemoteResultsScreen(jobId: jobId, title: title)));

class RemoteResultsScreen extends StatefulWidget {
  const RemoteResultsScreen({super.key, required this.jobId, this.title});
  final String jobId;
  final String? title;

  @override
  State<RemoteResultsScreen> createState() => _RemoteResultsScreenState();
}

class _RemoteResultsScreenState extends State<RemoteResultsScreen> {
  HistoryEntry? _entry;
  String? _error;

  @override
  void initState() {
    super.initState();
    final saved = context.read<HistoryStore>().byId(widget.jobId);
    if (saved != null) {
      _entry = saved;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ApiClient>().result(widget.jobId);
      if (!mounted) return;
      setState(() => _entry = HistoryEntry(id: widget.jobId, createdAt: DateTime.now().millisecondsSinceEpoch, title: widget.title ?? (r['source'] as Map?)?['title'] as String? ?? 'Item from a feed check', profileId: 'me', result: r, sourceUrl: (r['source'] as Map?)?['url'] as String?));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_entry != null) return ResultsScreen(entry: _entry!, saved: context.read<HistoryStore>().byId(widget.jobId) != null);
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: _error != null ? Padding(padding: const EdgeInsets.all(20), child: ErrorNote(_error!)) : const Center(child: CircularProgressIndicator()),
    );
  }
}

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.entry, this.saved = true});
  final HistoryEntry entry;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final api = context.read<ApiClient>();
    final r = entry.analysis;
    final ranked = r.ranked();
    final top = ranked.isEmpty ? const MapEntry('happy', 0.0) : ranked.first;
    final wb = r.wellbeing;
    final child = entry.profileId != 'me';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        actions: [
          if (saved)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(title: const Text('Delete this analysis?'), content: const Text('It is removed from this phone. The server keeps no video.'), actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                  ]),
                );
                if (ok == true && context.mounted) {
                  await context.read<HistoryStore>().remove(entry.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ---- header
          NlCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 92, child: NetThumb(url: api.thumbnailUrl(entry.id), emoji: moodEmoji(top.key))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800), maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    r.isImage ? 'Image · ${_date(entry.createdAt)}' : '${_date(entry.createdAt)} · ${_dur(r.duration)} · ${r.frames} frames',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  if (child) Padding(padding: const EdgeInsets.only(top: 8), child: Pill('For ${context.read<ProfilesStore>().nameOf(entry.profileId)}', tone: Tone.blue, icon: Icons.family_restroom)),
                  if (entry.sourceUrl != null && entry.sourceUrl!.startsWith('http'))
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36), alignment: Alignment.centerLeft),
                      onPressed: () => launchUrl(Uri.parse(entry.sourceUrl!), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Watch the original'),
                    ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // ---- dominant mood
          NlCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Dominant emotion', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(moodEmoji(top.key), style: const TextStyle(fontSize: 38)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(cap(top.key), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        Text(moodLabel(top.key, r.moodLabels), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                      ])),
                    ]),
                  ]),
                ),
                Ring(fraction: top.value / 100, center: '${top.value.toStringAsFixed(0)}%', sub: 'match', color: moodColor(top.key)),
              ]),
              if (r.verdict.isNotEmpty) ...[const SizedBox(height: 14), _Verdict(r.verdict)],
              if (r.confidenceLevel != null) ...[
                const SizedBox(height: 10),
                Text(
                  switch (r.confidenceLevel) {
                    'clear' => 'A clear read: one mood stands well ahead of the rest.',
                    'leaning' => 'Leaning ${top.key}, with other moods close behind.',
                    _ => 'A mixed read: several moods score about the same, so treat the top result as a starting point.',
                  },
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),

          // ---- key numbers
          _Stats(r: r),
          const SizedBox(height: 14),

          // ---- key moments
          if (r.keyframes.where((k) => k.flag == null).isNotEmpty) ...[
            NlCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionTitle('Key moments', subtitle: 'The frames that shaped this result'),
                SizedBox(
                  height: 168,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final k in r.keyframes.where((k) => k.flag == null))
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: 112,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: NetThumb(url: api.absolute(k.url), emoji: moodEmoji(k.mood), radius: 14, aspect: 3 / 4)),
                            const SizedBox(height: 6),
                            Text(r.isImage ? cap(k.mood ?? top.key) : '${k.t.toStringAsFixed(0)}s · ${cap(k.mood ?? top.key)}', style: t.textTheme.bodySmall),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          // ---- emotional profile
          _Profile(r: r),
          const SizedBox(height: 14),

          // ---- timeline
          if (!r.isImage && r.timeline.length >= 2) ...[
            NlCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionTitle('Emotion timeline', subtitle: 'Top 3 emotions over time'),
                TimelineChart(timeline: r.timeline, moodsToShow: r.ranked(r.visualAverages).take(3).map((e) => e.key).toList()),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          // ---- visual check
          if (r.safety != null && r.safety!.checked) ...[_VisualCheck(r: r, api: api), const SizedBox(height: 14)],

          // ---- wellbeing
          NlCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle('Wellbeing signal', trailing: Pill(wb.label, tone: toneFor(wb.level))),
              Text(wb.summary),
              if (wb.drivers.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [for (final d in wb.drivers.take(4)) Pill('${moodEmoji(d.key)} ${cap(d.key)} ${d.value.toStringAsFixed(0)}%')]),
              ],
              const SizedBox(height: 10),
              Text("Based on emotional tone only. It can't judge captions or comments.", style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              if (child && wb.level == WellbeingLevel.high) ...[
                const SizedBox(height: 12),
                const ErrorNote('If you think your child may be at risk, talk with them today and reach out to a counselor, doctor or local crisis service.'),
              ],
            ]),
          ),
          const SizedBox(height: 14),

          // ---- feedback
          _Feedback(entry: entry, saved: saved),
        ],
      ),
    );
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _dur(double s) => '${s ~/ 60}:${(s % 60).round().toString().padLeft(2, '0')}';
}

class _Verdict extends StatelessWidget {
  const _Verdict(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.auto_awesome, size: 18, color: t.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: t.colorScheme.onSecondaryContainer, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.r});
  final AnalysisResult r;

  @override
  Widget build(BuildContext context) {
    final cm = r.colorMetrics;
    final topVisual = r.ranked(r.visualAverages).firstOrNull?.key ?? '';
    final items = <(IconData, String, String)>[
      (Icons.visibility_outlined, 'Visual vibe', cap(topVisual)),
      if (!r.isImage) (Icons.music_note_outlined, 'Audio vibe', r.audioAvailable ? cap('${r.audio['dominant'] ?? ''}') : 'No audio'),
      if (!r.isImage) (Icons.speed, 'Pacing', '${r.pace} · ${(cm['cuts_per_minute'] ?? 0).toStringAsFixed(0)}/min'),
      (Icons.wb_sunny_outlined, 'Brightness', '${(cm['avg_brightness'] ?? 0).toStringAsFixed(0)}%'),
      if (r.isImage) (Icons.palette_outlined, 'Color richness', '${(cm['avg_saturation'] ?? 0).toStringAsFixed(0)}%'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: [
        for (final i in items)
          NlCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [Icon(i.$1, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(width: 6), Expanded(child: Text(i.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)))]),
              const SizedBox(height: 2),
              Text(i.$3, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
      ],
    );
  }
}

class _Profile extends StatefulWidget {
  const _Profile({required this.r});
  final AnalysisResult r;

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  String _src = 'combined';
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final scores = _src == 'visual' ? r.visualAverages : _src == 'audio' && r.audioAvailable ? r.audioAverages : r.averages;
    final rows = r.ranked(scores);
    final shown = _all ? rows : rows.take(8).toList();
    final t = Theme.of(context);
    return NlCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Emotional profile'),
        if (!r.isImage)
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: 'combined', label: Text('Combined')),
              const ButtonSegment(value: 'visual', label: Text('Visual')),
              ButtonSegment(value: 'audio', label: const Text('Audio'), enabled: r.audioAvailable),
            ],
            selected: {_src},
            onSelectionChanged: (s) => setState(() => _src = s.first),
          ),
        const SizedBox(height: 8),
        Text(
          _src == 'visual' ? 'From the video frames only.' : _src == 'audio' ? 'From the soundtrack only.' : r.audioAvailable ? 'Mostly from what the camera sees, with the soundtrack as a supporting signal.' : r.isImage ? 'From the image.' : 'Visual only. This video has no usable audio.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        MoodBars(entries: shown, labels: r.moodLabels),
        TextButton(onPressed: () => setState(() => _all = !_all), child: Text(_all ? 'Show top 8' : 'Show all ${rows.length} emotions')),
      ]),
    );
  }
}

class _VisualCheck extends StatelessWidget {
  const _VisualCheck({required this.r, required this.api});
  final AnalysisResult r;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sf = r.safety!;
    final flagged = sf.flagged;
    final frames = r.keyframes.where((k) => k.flag != null).toList();
    return NlCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Visual check', trailing: Pill(flagged ? 'Worth a look' : 'Nothing flagged', tone: flagged ? Tone.amber : Tone.green)),
        Text(flagged
            ? '${sf.flags.first.label} showed up in ${sf.flags.first.frames} of ${sf.flags.first.of} frames checked. Review the frame below and decide for yourself.'
            : 'We checked ${sf.framesChecked} ${sf.framesChecked == 1 ? 'frame' : 'frames'} and found nothing that looked revealing.'),
        if (frames.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(width: 130, child: NetThumb(url: api.absolute(frames.first.url), emoji: '🖼️', aspect: 3 / 4)),
        ],
        const SizedBox(height: 10),
        Text("An automatic screen for revealing or suggestive content. It is strict, so everyday dance or swimwear footage can show up here. It can't judge context, captions or comments.", style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Feedback extends StatefulWidget {
  const _Feedback({required this.entry, required this.saved});
  final HistoryEntry entry;
  final bool saved;

  @override
  State<_Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends State<_Feedback> {
  bool _fix = false;
  String? _mood;
  String? _msg;
  bool _busy = false;

  Future<void> _send(String rating, {String? corrected}) async {
    setState(() => _busy = true);
    try {
      final history = context.read<HistoryStore>();
      await context.read<ApiClient>().sendFeedback(widget.entry.id, rating, correctedMood: corrected);
      if (widget.saved) await history.setFeedback(widget.entry.id, rating);
      if (mounted) {
        setState(() {
          _msg = 'Thanks, feedback recorded. It helps the analysis learn.';
          _fix = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NlCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Was this accurate?', subtitle: 'Your feedback improves future results'),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _send('good'), icon: const Icon(Icons.thumb_up_outlined, size: 18), label: const Text('Spot on'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => setState(() => _fix = true), icon: const Icon(Icons.thumb_down_outlined, size: 18), label: const Text('Off'))),
        ]),
        if (_fix) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _mood,
            decoration: const InputDecoration(labelText: 'What should it have been?'),
            items: [for (final m in moods.values) DropdownMenuItem(value: m.key, child: Text('${m.emoji} ${cap(m.key)}'))],
            onChanged: (v) => setState(() => _mood = v),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _busy ? null : () => _send('bad', corrected: _mood), child: const Text('Send feedback')),
        ],
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!)),
      ]),
    );
  }
}

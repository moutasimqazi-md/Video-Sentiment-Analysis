import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/auth.dart';
import '../../core/models.dart';
import '../../core/stores.dart';
import '../widgets/common.dart';
import '../widgets/tab_bar.dart';
import 'plans_screen.dart';
import 'results_screen.dart';

const _maxItems = 10;
const _maxBytes = 300 * 1024 * 1024;

class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  final _links = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _files = [];
  int _tab = 0; // 0 = links, 1 = files
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _links.dispose();
    super.dispose();
  }

  List<String> get _parsedLinks => _links.text.split(RegExp(r'[\s,]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() => _links.text = _links.text.trim().isEmpty ? text : '${_links.text.trim()}\n$text');
  }

  Future<void> _pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f != null) await _add([f]);
  }

  Future<void> _pickImages() async {
    final fs = await _picker.pickMultiImage();
    if (fs.isNotEmpty) await _add(fs);
  }

  Future<void> _add(List<XFile> picked) async {
    final problems = <String>[];
    for (final f in picked) {
      if (_files.length >= _maxItems) {
        problems.add('You can add up to $_maxItems at a time.');
        break;
      }
      if (await f.length() > _maxBytes) {
        problems.add('${f.name} is over 300 MB.');
        continue;
      }
      _files.add(f);
    }
    setState(() => _error = problems.isEmpty ? null : problems.toSet().join(' '));
  }

  Future<void> _run() async {
    final queue = context.read<JobQueue>();
    final profile = context.read<ProfilesStore>().active;
    setState(() => _error = null);
    final auth = context.read<AuthController>();
    final count = _tab == 0 ? _parsedLinks.length : _files.length;
    if (auth.me != null && count > 0 && count > auth.me!.remaining) {
      await showUpgradePrompt(context, auth.me!.remaining <= 0 ? "You have used this month's ${auth.me!.quota} analyses on the ${auth.me!.plan.name} plan." : 'You have ${auth.me!.remaining} ${auth.me!.remaining == 1 ? 'analysis' : 'analyses'} left this month, but added $count.');
      return;
    }
    if (!mounted) return;
    if (_tab == 0) {
      final links = _parsedLinks;
      if (links.isEmpty) return setState(() => _error = 'Paste a link first.');
      if (links.any((l) => !RegExp(r'^https?://', caseSensitive: false).hasMatch(l))) return setState(() => _error = 'Paste full links starting with https://');
      if (links.length > _maxItems) return setState(() => _error = 'Add up to $_maxItems links at a time.');
      setState(() => _busy = true);
      for (final l in links) {
        await queue.addLink(l, profileId: profile);
      }
      _links.clear();
    } else {
      if (_files.isEmpty) return setState(() => _error = 'Choose a video or image first.');
      setState(() => _busy = true);
      final files = List<XFile>.from(_files);
      _files.clear();
      for (final f in files) {
        await queue.addFile(() => f.openRead(), await f.length(), f.name, profileId: profile, mime: f.mimeType ?? _guessMime(f.name)); // one upload at a time
      }
    }
    if (mounted) setState(() => _busy = false);
    auth.refresh(); // the server counted these against the plan
  }

  String? _guessMime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.mp4')) return 'video/mp4';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final profiles = context.watch<ProfilesStore>();
    final jobs = context.watch<JobQueue>();

    final me = context.watch<AuthController>().me;
    return Scaffold(
      appBar: const NlTabBar(title: 'Analyze'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (me != null) ...[
            NlCard(
              padding: const EdgeInsets.all(14),
              onTap: () => openPlans(context),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(me.outOfAnalyses ? "You've used all ${me.quota} analyses this month" : '${me.remaining} of ${me.quota} analyses left this month', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: me.usedFraction, minHeight: 8)),
                  ]),
                ),
                const SizedBox(width: 12),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Pill(me.remaining <= 2 ? 'Upgrade' : me.plan.name, tone: me.remaining <= 2 ? Tone.coral : Tone.neutral))),
              ]),
            ),
            const SizedBox(height: 14),
          ],
          NlCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: profiles.active,
                decoration: const InputDecoration(labelText: 'Who is this for?', prefixIcon: Icon(Icons.person_outline)),
                items: [
                  const DropdownMenuItem(value: 'me', child: Text('Me (my own content)')),
                  for (final c in profiles.children) DropdownMenuItem(value: c.id, child: Text('${c.name}${c.age != null ? ' (${c.age})' : ''} · child')),
                ],
                onChanged: (v) => v == null ? null : profiles.setActive(v),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 0, icon: Icon(Icons.link), label: Text('Links')), ButtonSegment(value: 1, icon: Icon(Icons.upload_file), label: Text('Files'))],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() {
                  _tab = s.first;
                  _error = null;
                }),
              )),
              const SizedBox(height: 14),
              if (_tab == 0) ...[
                TextField(
                  controller: _links,
                  minLines: 3,
                  maxLines: 6,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Reel, Short or video links',
                    hintText: 'https://www.instagram.com/reel/…\nOne link per line to queue several',
                    alignLabelWithHint: true,
                    suffixIcon: IconButton(tooltip: 'Paste', icon: const Icon(Icons.content_paste), onPressed: _paste),
                  ),
                ),
                const SizedBox(height: 8),
                Text('In Instagram: open the Reel, tap Share, then Copy link. Private account? Screen-record it and use Files.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ] else ...[
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _pickVideo, icon: const Icon(Icons.videocam_outlined), label: const Text('Video'))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: _pickImages, icon: const Icon(Icons.image_outlined), label: const Text('Images'))),
                ]),
                const SizedBox(height: 8),
                Text('MP4, MOV, WEBM, JPG, PNG, WEBP · up to 300 MB each · add up to $_maxItems', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                for (var i = 0; i < _files.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: t.colorScheme.secondaryContainer, child: Icon((_files[i].mimeType ?? '').startsWith('image') ? Icons.image : Icons.movie, color: t.colorScheme.primary)),
                    title: Text(_files[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(icon: const Icon(Icons.close), tooltip: 'Remove', onPressed: () => setState(() => _files.removeAt(i))),
                  ),
              ],
              if (_error != null) ...[const SizedBox(height: 12), ErrorNote(_error!)],
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _run, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome), label: const Text('Analyze'))),
              const SizedBox(height: 8),
              Center(child: Text('Videos are processed securely and deleted right after analysis.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center)),
            ]),
          ),
          if (jobs.jobs.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionTitle('Your analyses', trailing: jobs.jobs.any((j) => !j.active) ? TextButton(onPressed: jobs.clearFinished, child: const Text('Clear finished')) : null),
            for (final j in jobs.jobs.take(12)) Padding(padding: const EdgeInsets.only(bottom: 10), child: _JobTile(job: j)),
          ],
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final queue = context.read<JobQueue>();
    return NlCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(job.isImage ? Icons.image_outlined : Icons.movie_outlined, size: 20, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (job.state == JobState.done) const Pill('Ready', tone: Tone.green, icon: Icons.check) else if (job.state == JobState.error) const Pill('Failed', tone: Tone.coral),
        ]),
        const SizedBox(height: 8),
        if (job.active) ...[
          ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: job.state == JobState.uploading || job.progress == 0 ? null : job.progress.clamp(0, 1), minHeight: 8)),
          const SizedBox(height: 6),
          Text(job.stage, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
        if (job.state == JobState.error) ...[
          Text(job.error ?? 'Failed', style: TextStyle(color: t.colorScheme.primary)),
          if ((job.error ?? '').contains('Upgrade')) TextButton(onPressed: () => openPlans(context), child: const Text('See plans')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (job.url != null) FilledButton.tonal(style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: () => queue.retry(job), child: const Text('Try again')),
            TextButton(onPressed: () => queue.dismiss(job), child: const Text('Dismiss')),
          ]),
        ],
        if (job.state == JobState.done) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () {
                final e = job.entryId == null ? null : context.read<HistoryStore>().byId(job.entryId!);
                if (e != null) openResult(context, e);
              },
              child: const Text('View results'),
            ),
            TextButton(onPressed: () => queue.dismiss(job), child: const Text('Dismiss')),
          ]),
        ],
      ]),
    );
  }
}

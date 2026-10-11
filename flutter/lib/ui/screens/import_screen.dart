import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/imports/habits.dart';
import '../../core/imports/import_store.dart';
import '../../core/imports/parse.dart';
import '../../core/stores.dart';
import '../widgets/common.dart';
import '../widgets/tab_bar.dart';
import 'habits_report_screen.dart';

/// Import: pick the Instagram / Google Takeout export, see what was found, and build a habits report. Read on this phone only.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, this.profile});
  final String? profile;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  Map<String, dynamic>? _found;
  bool _reading = false, _building = false, _consent = false;
  String? _error;
  late String _profile = widget.profile ?? 'me';

  Future<void> _pick() async {
    setState(() => _error = null);
    List<PlatformFile> res;
    try {
      res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['zip', 'json', 'csv', 'html', 'htm']);
    } catch (_) {
      setState(() => _error = "The file picker couldn't open. Check that NeuroLens can access your files and try again.");
      return;
    }
    final paths = res.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    setState(() {
      _reading = true;
      _found = null;
    });
    try {
      final r = await readExports(paths);
      if (!mounted) return;
      final ev = (r['events'] as Map).cast<String, dynamic>();
      final n = (ev['ig'] as List).length + (ev['yt'] as List).length;
      String? err;
      if ((r['sources'] as int) == 0) {
        if ((r['igHtml'] as int) > 0) {
          err = 'This looks like an Instagram export in HTML format. Request it again and choose JSON as the format.';
        } else if ((r['totalEntries'] as int) == 0) {
          err = "We couldn't find any files to read. Choose a .zip from Instagram or Google Takeout.";
        } else {
          err = 'None of the history files we know were found. For Instagram include Likes, Saved, Story interactions and Ads information (posts / videos viewed). For YouTube include History. Use JSON format.';
        }
      } else if (n == 0) {
        err = 'The files were read but contained no history entries.${(r['problems'] as List).isNotEmpty ? ' ${(r['problems'] as List).first}' : ''}';
      }
      setState(() {
        _reading = false;
        _error = err;
        _found = err == null ? r : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _reading = false;
          _error = 'Something went wrong while reading those files.';
        });
      }
    }
  }

  Future<void> _build() async {
    final f = _found;
    if (f == null) return;
    if (_profile != 'me' && !_consent) {
      setState(() => _error = "Please confirm your child knows you're reviewing their data.");
      return;
    }
    final store = context.read<ImportStore>();
    final ev = (f['events'] as Map).cast<String, dynamic>();
    setState(() {
      _building = true;
      _error = null;
    });
    try {
      final lex = await rootBundle.loadString('assets/lexicon.json');
      final meta = {'files': f['files'], 'ignoredPrivate': f['ignoredPrivate']};
      final built = <String>[];
      for (final src in ImportStore.platforms) {
        final list = (ev[src] as List).cast<Map<String, dynamic>>();
        if (list.isEmpty) continue;
        await store.save(_profile, src, await buildReport(src, list, lex, meta)); // a separate report per platform; nothing is combined
        built.add(src);
      }
      if (!mounted) return;
      setState(() {
        _building = false;
        _found = null;
        _consent = false;
      });
      if (built.length == 1) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => HabitsReportScreen(profile: _profile, src: built.first)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Two separate reports were created')));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _building = false;
          _error = "We couldn't build the report. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final store = context.watch<ImportStore>();
    final profiles = context.watch<ProfilesStore>();
    final saved = store.all();

    Widget steps(IconData icon, String title, List<String> items, String note, String url, String linkLabel) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: NlCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: t.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(icon, color: t.colorScheme.primary),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('How to get your file'),
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 22, height: 22, alignment: Alignment.center, margin: const EdgeInsets.only(right: 10, top: 1), decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, shape: BoxShape.circle), child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: t.colorScheme.primary))),
                      Expanded(child: Text(items[i])),
                    ])),
                  Text(note, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new, size: 18), label: Text(linkLabel)),
                ],
              ),
            ),
          ),
        );

    final f = _found;
    return Scaffold(
      appBar: const NlTabBar(title: 'Import'),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        Text('Download your history from Instagram or YouTube, add the file here, and get a habits report: when you scroll, how much, what it is about, and what to watch out for.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        NlCard(color: t.colorScheme.secondaryContainer, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.shield_outlined, color: t.colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text('Your files stay on your phone', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)))]),
          const SizedBox(height: 8),
          for (final s in const [
            'Everything is read and analysed on this phone. Your export is never uploaded.',
            'Only history files are opened (watched, liked, saved, searches). Private messages and personal details are skipped and never read.',
            'Only a summary is kept, on this phone, for this account. You can delete it any time.',
          ])
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Padding(padding: EdgeInsets.only(top: 2, right: 8), child: Icon(Icons.check, size: 16)), Expanded(child: Text(s, style: t.textTheme.bodySmall))])),
        ])),
        const SizedBox(height: 14),
        steps(Icons.camera_alt_outlined, 'Instagram', const [
          'Open Accounts Center → Your information and permissions → Download your information.',
          'Choose your account, then Some of your information. Tick Likes, Saved, Comments, Story interactions, Posts and Videos viewed (Ads information), Followers and following, Searches.',
          'Set the date range to Last year or All time, the format to JSON, and media quality to the lowest.',
          "Wait for Instagram's email, download the .zip, and add it below.",
        ], 'Instagram only keeps about the last 7 days of viewed reels in an export. Likes can go back a year or more.', 'https://accountscenter.instagram.com/info_and_permissions/dyi/', "Open Instagram's export page"),
        steps(Icons.play_circle_outline, 'YouTube (Google Takeout)', const [
          'Go to takeout.google.com and choose Deselect all.',
          'Tick YouTube and YouTube Music, then All YouTube data included, and keep history.',
          'Under Multiple formats, change history from HTML to JSON. This matters: HTML dates depend on your language.',
          'Create the export, download the .zip, and add it below. You can add both at once. Each gets its own report.',
        ], "YouTube history lists titles and channels but not watch time, so the report counts videos instead of minutes.", 'https://takeout.google.com/', 'Open Google Takeout'),
        const SizedBox(height: 6),
        const SectionTitle('Add your files'),
        NlCard(
          onTap: _reading || _building ? null : _pick,
          child: SizedBox(
            width: double.infinity,
            child: _reading
                ? Column(children: [const SizedBox(height: 8), const CircularProgressIndicator(), const SizedBox(height: 14), const Text('Reading your files…', style: TextStyle(fontWeight: FontWeight.w700)), Text('Big exports can take a minute.', style: t.textTheme.bodySmall), const SizedBox(height: 8)])
                : Column(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(18)), child: Icon(Icons.upload_file, color: t.colorScheme.primary, size: 28)),
                    const SizedBox(height: 12),
                    const Text('Choose your ZIP file', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('Instagram export or Google Takeout (.zip, or the .json files)', textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ]),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), ErrorNote(_error!)],
        if (f != null) ...[
          const SizedBox(height: 16),
          _Found(found: f),
          const SizedBox(height: 12),
          NlCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<String>(
              initialValue: _profile,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Whose data is this?', prefixIcon: Icon(Icons.person_outline)),
              items: [const DropdownMenuItem(value: 'me', child: Text('Me')), for (final c in profiles.children) DropdownMenuItem(value: c.id, child: Text('${c.name} (child)', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() {
                _profile = v ?? 'me';
                _consent = false;
              }),
            ),
            if (_profile != 'me')
              CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, value: _consent, onChanged: (v) => setState(() => _consent = v ?? false), title: const Text("My child knows I'm reviewing their data.")),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _building ? null : _build, icon: _building ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.insights), label: Text(_building ? 'Building…' : 'Build my report'))),
            if (store.sourcesFor(_profile).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('A newer import replaces the earlier one for the same platform, and the report shows what changed.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))),
          ])),
        ],
        if (saved.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionTitle('Saved reports'),
          for (final (id, src, r) in saved)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NlCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HabitsReportScreen(profile: id, src: src))),
                child: Row(children: [
                  Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(14)), child: Text('${(r['overall'] as Map)['score'] ?? '–'}', style: TextStyle(fontWeight: FontWeight.w800, color: t.colorScheme.primary))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(profiles.nameOf(id) == 'Me' ? 'My ${ImportStore.platformNames[src]} report' : "${profiles.nameOf(id)}'s ${ImportStore.platformNames[src]} report", style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('Imported ${DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch((r['createdAt'] as num).toInt()))}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ])),
                  const Icon(Icons.chevron_right),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}

class _Found extends StatelessWidget {
  const _Found({required this.found});
  final Map<String, dynamic> found;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ev = (found['events'] as Map).cast<String, dynamic>();
    final total = (ev['ig'] as List).length + (ev['yt'] as List).length;
    final ranges = (found['ranges'] as Map).cast<String, dynamic>();
    final rows = [for (final e in ranges.entries) if (((e.value as Map)['n'] as int) > 0) MapEntry(e.key, (e.value as Map).cast<String, int>())]..sort((a, b) => b.value['n']!.compareTo(a.value['n']!));
    String d(int s) => s == 0 ? '–' : DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(s * 1000));
    final notes = <String>[];
    final igRange = ranges['igVideosWatched'] as Map?;
    if ((ev['ig'] as List).isNotEmpty) {
      if (igRange != null && (igRange['from'] as int) > 0 && ((igRange['to'] as int) - (igRange['from'] as int)) / 86400 < 14) {
        notes.add("Instagram only included ${(((igRange['to'] as int) - (igRange['from'] as int)) / 86400).round().clamp(1, 999)} days of watched reels. That's how Instagram exports it. Longer-term patterns come from your likes and stories.");
      }
      if (ranges['igLikes'] == null) notes.add('No likes file was found. Add "Likes" to your Instagram export for the best long-term picture.');
    }
    if ((ev['yt'] as List).isNotEmpty) {
      if ((found['adsSkipped'] as int) > 0) notes.add('${found['adsSkipped']} entries that were Google Ads were left out of your YouTube history.');
      if (ranges['ytWatch'] == null) notes.add('No YouTube watch history was found. Choose the "history" option in Takeout.');
    }
    if ((found['igHtml'] as int) > 0) notes.add('Some Instagram files are in HTML format and were skipped. Request the export in JSON for the full picture.');
    notes.addAll((found['problems'] as List).cast<String>());

    return NlCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What we found', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('${NumberFormat.decimalPattern().format(total)} history items across ${rows.length} kinds of data.${(found['ignoredPrivate'] as int) > 0 ? ' ${NumberFormat.decimalPattern().format(found['ignoredPrivate'])} private files (messages and personal details) were ignored and never read.' : ''}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 10),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(r.key.startsWith('ig') ? Icons.camera_alt_outlined : Icons.play_circle_outline, size: 18, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(importLabels[r.key] ?? r.key, style: const TextStyle(fontWeight: FontWeight.w700)), Text('${d(r.value['from']!)} to ${d(r.value['to']!)}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))])),
            Text(NumberFormat.decimalPattern().format(r.value['n']), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
      for (final n in notes) Padding(padding: const EdgeInsets.only(top: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, size: 16, color: t.colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text(n, style: t.textTheme.bodySmall))])),
    ]));
  }
}

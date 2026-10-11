import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/moods.dart';
import '../../core/stores.dart';
import '../../core/wellbeing.dart';
import '../shell_nav.dart';
import '../widgets/common.dart';
import 'results_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.profileId});
  final String? profileId; // opened from Family: only that profile

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _q = '';
  String? _profile; // null = everyone
  String? _mood;
  bool _flaggedOnly = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profileId;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final history = context.watch<HistoryStore>();
    final profiles = context.watch<ProfilesStore>();
    final api = context.read<ApiClient>();
    final q = _q.trim().toLowerCase();
    final items = history.items.where((e) {
      if (_profile != null && e.profileId != _profile) return false;
      if (_mood != null && e.analysis.dominant != _mood) return false;
      if (_flaggedOnly && !(e.analysis.wellbeing.level != WellbeingLevel.calm || (e.analysis.safety?.flagged ?? false))) return false;
      if (q.isNotEmpty && !e.title.toLowerCase().contains(q) && !e.analysis.dominant.contains(q)) return false;
      return true;
    }).toList();
    final usedMoods = history.items.map((e) => e.analysis.dominant).toSet().toList()..sort();

    return Scaffold(
      appBar: AppBar(title: Text(widget.profileId == null ? 'History' : '${profiles.nameOf(widget.profileId!)}: history')),
      body: history.items.isEmpty
          ? EmptyState(
              icon: Icons.history,
              title: 'Nothing here yet',
              text: 'Every analysis you run is saved here, on this phone.',
              action: FilledButton(onPressed: () => context.read<ShellNav>().go(ShellNav.analyze), child: const Text('Analyze something')),
            )
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(hintText: 'Search title or mood', prefixIcon: Icon(Icons.search))),
              ),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  if (widget.profileId == null)
                    for (final p in [('me', 'Me'), ...profiles.children.map((c) => (c.id, c.name))])
                      Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(label: Text(p.$2), selected: _profile == p.$1, onSelected: (v) => setState(() => _profile = v ? p.$1 : null))),
                  Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(avatar: const Icon(Icons.flag_outlined, size: 16), label: const Text('Worth a look'), selected: _flaggedOnly, onSelected: (v) => setState(() => _flaggedOnly = v))),
                  for (final m in usedMoods)
                    Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(label: Text('${moodEmoji(m)} ${cap(m)}'), selected: _mood == m, onSelected: (v) => setState(() => _mood = v ? m : null))),
                ]),
              ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(icon: Icons.search_off, title: 'No matches', text: 'Try a different search or clear a filter.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = items[i];
                          final r = e.analysis;
                          final wb = r.wellbeing;
                          return Dismissible(
                            key: ValueKey(e.id),
                            direction: DismissDirection.endToStart,
                            background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(20)), child: Icon(Icons.delete_outline, color: t.colorScheme.primary)),
                            onDismissed: (_) {
                              history.remove(e.id);
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(SnackBar(content: const Text('Analysis deleted'), action: SnackBarAction(label: 'Undo', onPressed: () => history.add(e))));
                            },
                            child: NlCard(
                              padding: const EdgeInsets.all(12),
                              onTap: () => openResult(context, e),
                              child: Row(children: [
                                SizedBox(width: 64, child: NetThumb(url: api.thumbnailUrl(e.id), emoji: moodEmoji(r.dominant), radius: 12)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Wrap(spacing: 6, runSpacing: 4, children: [
                                      Pill('${moodEmoji(r.dominant)} ${cap(r.dominant)}', tone: Tone.blue),
                                      Pill(wb.label, tone: toneFor(wb.level)),
                                      if (r.safety?.flagged ?? false) const Pill('Revealing?', tone: Tone.amber),
                                      if (e.profileId != 'me') Pill(profiles.nameOf(e.profileId), icon: Icons.family_restroom),
                                    ]),
                                    const SizedBox(height: 4),
                                    Text(_date(e.createdAt) + (r.isImage ? ' · Image' : ''), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                                  ]),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ]),
    );
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }
}

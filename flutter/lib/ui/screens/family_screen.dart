import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth.dart';
import '../../core/stores.dart';
import '../../core/models.dart';
import '../../core/moods.dart';
import '../../core/wellbeing.dart';
import '../shell_nav.dart';
import '../widgets/common.dart';
import '../widgets/tab_bar.dart';
import 'feed_screen.dart';
import 'history_screen.dart';
import 'plans_screen.dart';

class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final me = context.read<AuthController>().me;
    final have = context.read<ProfilesStore>().children.length;
    if (me != null && have >= me.plan.children) {
      await showUpgradePrompt(context, me.plan.children == 0 ? 'The ${me.plan.name} plan has no child profiles. Upgrade to add one.' : 'The ${me.plan.name} plan includes ${me.plan.children} child profiles. Upgrade to add more.');
      return;
    }
    if (!context.mounted) return;
    final name = TextEditingController();
    final age = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add a child profile', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Only a name or nickname and an age. It stays on this phone.', style: Theme.of(c).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name or nickname'), autofocus: true),
          const SizedBox(height: 12),
          TextField(controller: age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age (optional)')),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add profile')),
        ]),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && context.mounted) {
      await context.read<ProfilesStore>().add(name.text, int.tryParse(age.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final profiles = context.watch<ProfilesStore>();
    final history = context.watch<HistoryStore>();
    final weekAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;

    return Scaffold(
      appBar: const NlTabBar(title: 'Family'),
      floatingActionButton: profiles.children.isEmpty ? null : FloatingActionButton.extended(onPressed: () => _add(context), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add child')),
      body: profiles.children.isEmpty
          ? EmptyState(
              icon: Icons.family_restroom,
              title: 'No child profiles yet',
              text: 'Add one to review the Reels they watch, see a weekly summary, and get alerts when something needs a look.',
              action: FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('Add a child')),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
              for (final c in profiles.children) ...[
                _ChildCard(child: c, week: history.forProfile(c.id).where((e) => e.createdAt >= weekAgo).toList(), total: history.forProfile(c.id).length),
                const SizedBox(height: 14),
              ],
              NlCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Talking about what they watch'),
                  for (final tip in const [
                    'Ask open questions: "What did you like about that one?" works better than "Why are you watching that?"',
                    'Watch a few Reels together and talk about how they make you both feel.',
                    'Agree on screen-free times, for example the hour before bed. Heavy content hits hardest late at night.',
                  ])
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.check_circle_outline, size: 18, color: t.colorScheme.primary), const SizedBox(width: 10), Expanded(child: Text(tip))])),
                ]),
              ),
            ]),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child, required this.week, required this.total});
  final ChildProfile child;
  final List<HistoryEntry> week;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final roll = WellbeingRollup.of(week.map((e) => e.analysis.averages), week.map((e) => e.analysis.dominant));
    final profiles = context.read<ProfilesStore>();
    return NlCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 22, backgroundColor: t.colorScheme.secondaryContainer, child: Text(child.name.isEmpty ? '?' : child.name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, color: t.colorScheme.primary))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(child.name, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text('${child.age != null ? 'Age ${child.age} · ' : ''}$total ${total == 1 ? 'analysis' : 'analyses'}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ])),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(title: Text('Remove ${child.name}?'), content: const Text("This deletes the profile and its analyses from this phone."), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove'))]),
                );
                if (ok == true && context.mounted) {
                  await context.read<HistoryStore>().removeProfile(child.id);
                  await profiles.remove(child.id);
                }
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Remove profile'))],
          ),
        ]),
        const SizedBox(height: 14),
        if (week.isEmpty)
          Text('No analyses in the last 7 days.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant))
        else ...[
          Row(children: [
            Pill(Wellbeing(roll.overall, 0, const []).label, tone: toneFor(roll.overall)),
            const SizedBox(width: 8),
            Text('${week.length} this week · ${roll.heavyShare}% heavy tone', style: t.textTheme.bodySmall),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [for (final m in roll.mix.take(4)) Pill('${moodEmoji(m.key)} ${cap(m.key)} ${m.value.toStringAsFixed(0)}%')]),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
            onPressed: () {
              profiles.setActive(child.id);
              context.read<ShellNav>().go(ShellNav.analyze);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Analyze a Reel'),
          ),
          OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen(profileId: child.id))), icon: const Icon(Icons.history, size: 18), label: const Text('History')),
          OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FeedScreen(profileId: child.id))), icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('Feed monitoring')),
        ]),
      ]),
    );
  }
}

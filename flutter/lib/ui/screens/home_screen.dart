import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/moods.dart';
import '../../core/stores.dart';
import '../../core/wellbeing.dart';
import '../shell_nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tab_bar.dart';
import '../../core/alerts.dart';
import 'alerts_screen.dart';
import 'history_screen.dart';
import 'plans_screen.dart';
import 'settings_screen.dart';
import 'results_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final history = context.watch<HistoryStore>();
    final profiles = context.watch<ProfilesStore>();
    final api = context.read<ApiClient>();
    final me = context.watch<AuthController>().me;
    final unread = context.select<AlertsController, int>((a) => a.unread); // shown on the Alerts shortcut
    final mine = history.forProfile('me');
    final weekAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final week = mine.where((e) => e.createdAt >= weekAgo).toList();
    final roll = WellbeingRollup.of(week.map((e) => e.analysis.averages), week.map((e) => e.analysis.dominant));
    final mix = WellbeingRollup.of(mine.take(30).map((e) => e.analysis.averages), mine.take(30).map((e) => e.analysis.dominant)).mix.take(5).toList();

    return Scaffold(
      appBar: const NlTabBar(title: 'NeuroLens'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(me == null ? _greeting : '$_greeting, ${me.displayName}', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('Here is what your content feels like.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),

          // ---- analyze CTA
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFFD63B32), Color(0xFFC9332A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Analyze a Reel, video or image', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Paste a link or choose a file. You can add several and keep browsing.', style: TextStyle(color: Colors.white, height: 1.35)),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: NlColors.coralInk),
                onPressed: () => context.read<ShellNav>().go(ShellNav.analyze),
                icon: const Icon(Icons.add),
                label: const Text('New analysis'),
              )),
            ]),
          ),
          const SizedBox(height: 14),
          if (me != null)
            NlCard(
              padding: const EdgeInsets.all(14),
              onTap: () => openPlans(context),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.workspace_premium_outlined, color: t.colorScheme.primary)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${me.plan.name} · ${me.remaining} of ${me.quota} analyses left', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: me.usedFraction, minHeight: 7)),
                ])),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ]),
            ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _Quick(icon: Icons.history, label: 'History', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen())))),
            const SizedBox(width: 10),
            Expanded(child: _Quick(icon: Icons.notifications_outlined, label: 'Alerts', badge: unread, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AlertsScreen())))),
            const SizedBox(width: 10),
            Expanded(child: _Quick(icon: Icons.workspace_premium_outlined, label: 'Plans', onTap: () => openPlans(context))),
            const SizedBox(width: 10),
            Expanded(child: _Quick(icon: Icons.settings_outlined, label: 'Settings', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())))),
          ]),
          const SizedBox(height: 18),

          if (mine.isEmpty)
            NlCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Get started', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Your results and weekly summary appear here. Pick where to begin:', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                _Step(icon: Icons.add_circle_outline, title: 'Analyze a Reel', sub: 'Paste a link or choose a video', onTap: () => context.read<ShellNav>().go(ShellNav.analyze)),
                _Step(icon: Icons.upload_file_outlined, title: 'Import your history', sub: 'Instagram or YouTube export → habits report', onTap: () => context.read<ShellNav>().go(ShellNav.import)),
                _Step(icon: Icons.visibility_outlined, title: 'Check a feed', sub: 'Sign in to Instagram and review what it shows', onTap: () => context.read<ShellNav>().go(ShellNav.feed)),
              ]),
            )
          else ...[
            // ---- this week
            Row(children: [
              Expanded(child: _Stat(label: 'Analyses', value: '${mine.length}', icon: Icons.analytics_outlined)),
              const SizedBox(width: 10),
              Expanded(child: _Stat(label: 'This week', value: '${week.length}', icon: Icons.calendar_today_outlined)),
              const SizedBox(width: 10),
              Expanded(child: _Stat(label: 'Heavy tone', value: week.isEmpty ? '–' : '${roll.heavyShare}%', icon: Icons.favorite_border)),
            ]),
            const SizedBox(height: 18),
            NlCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionTitle('Your mood mix', subtitle: 'From your last ${mine.take(30).length} analyses', trailing: week.isEmpty ? null : Pill(Wellbeing(roll.overall, 0, const []).label, tone: toneFor(roll.overall))),
                MoodBars(entries: mix),
              ]),
            ),
            const SizedBox(height: 18),
            SectionTitle('Recent', trailing: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen())), child: const Text('See all'))),
            SizedBox(
              height: 190,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final e in mine.take(10))
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 118,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => openResult(context, e),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: NetThumb(url: api.thumbnailUrl(e.id), emoji: moodEmoji(e.analysis.dominant))),
                          const SizedBox(height: 6),
                          Text('${moodEmoji(e.analysis.dominant)} ${cap(e.analysis.dominant)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ],

          // ---- family nudge
          if (profiles.children.isEmpty) ...[
            const SizedBox(height: 18),
            NlCard(
              onTap: () => context.read<ShellNav>().go(ShellNav.family),
              child: Row(children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.family_restroom, color: t.colorScheme.primary)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Looking after a child?', style: TextStyle(fontWeight: FontWeight.w800)),
                  Text('Add a profile to review the Reels they watch and get alerts.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ])),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return NlCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: t.colorScheme.primary),
        const SizedBox(height: 8),
        Text(value, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.onTap, this.badge = 0});
  final int badge;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return MergeSemantics(child: Semantics(button: true, child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: t.colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.colorScheme.outlineVariant)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon, color: t.colorScheme.primary)),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    )));
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: t.colorScheme.primary)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(sub),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

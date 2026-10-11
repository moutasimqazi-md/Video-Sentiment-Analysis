import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alerts.dart';
import '../../core/stores.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'feed_screen.dart';
import 'results_screen.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final alerts = context.watch<AlertsController>();
    final profiles = context.read<ProfilesStore>();

    Widget body;
    if (alerts.alerts.isEmpty) {
      body = RefreshIndicator(
        onRefresh: alerts.refresh,
        child: ListView(children: [
          const SizedBox(height: 80),
          if (alerts.error != null) Padding(padding: const EdgeInsets.all(16), child: ErrorNote(alerts.error!)),
          const EmptyState(icon: Icons.notifications_none, title: 'No alerts yet', text: 'They appear here when a feed check finds something worth a look.'),
        ]),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: alerts.refresh,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: alerts.alerts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final a = alerts.alerts[i];
            final (icon, tone) = switch (a.level) { 'high' => (Icons.error_outline, Tone.coral), 'watch' => (Icons.visibility_outlined, Tone.amber), _ => (Icons.check_circle_outline, Tone.green) };
            return NlCard(
              color: a.seen ? null : t.colorScheme.surfaceContainerHighest,
              onTap: () {
                alerts.markRead([a.id]);
                if (a.jobId != null) {
                  openRemoteResult(context, a.jobId!);
                } else {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => FeedScreen(profileId: a.profile)));
                }
              },
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: switch (tone) { Tone.coral => t.colorScheme.primary, Tone.amber => NlColors.amber, _ => NlColors.green }),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(a.body, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text('${profiles.nameOf(a.profile)} · ${_ago(a.createdAt)}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ])),
                if (!a.seen) Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: t.colorScheme.primary, shape: BoxShape.circle)),
              ]),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts'), actions: [if (alerts.unread > 0) TextButton(onPressed: () => alerts.markRead(const []), child: const Text('Mark all read'))]),
      body: body,
    );
  }

  static String _ago(double ts) {
    final m = ((DateTime.now().millisecondsSinceEpoch / 1000 - ts) / 60).round();
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    if (m < 1440) return '${(m / 60).round()} h ago';
    return '${(m / 1440).round()} d ago';
  }
}

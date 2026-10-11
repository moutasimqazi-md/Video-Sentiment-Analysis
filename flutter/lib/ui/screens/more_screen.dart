import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alerts.dart';
import '../../core/auth.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'alerts_screen.dart';
import 'history_screen.dart';
import 'plans_screen.dart';
import 'settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final unread = context.watch<AlertsController>().unread;
    final me = context.watch<AuthController>().me;

    Widget tile(IconData icon, String title, String sub, VoidCallback onTap, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: NlCard(
            onTap: onTap,
            child: Row(children: [
              Container(width: 46, height: 46, decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: t.colorScheme.primary)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), Text(sub, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))])),
              ?trailing,
              const Icon(Icons.chevron_right),
            ]),
          ),
        );

    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      appBar: AppBar(title: const Text('Account & settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        tile(Icons.account_circle_outlined, me?.displayName ?? 'Account', me?.email ?? 'Sign in', () => go(const AccountScreen())),
        tile(Icons.workspace_premium_outlined, 'Plans & usage', me == null ? 'See plans' : '${me.plan.name} · ${me.remaining} of ${me.quota} analyses left', () => go(const PlansScreen()),
            trailing: me != null && me.outOfAnalyses ? const Padding(padding: EdgeInsets.only(right: 6), child: Pill('Upgrade', tone: Tone.coral)) : null),
        tile(Icons.history, 'History', 'Everything you have analysed', () => go(const HistoryScreen())),
        tile(Icons.notifications_outlined, 'Alerts', unread > 0 ? '$unread unread' : 'Nothing new', () => go(const AlertsScreen()),
            trailing: unread > 0 ? Padding(padding: const EdgeInsets.only(right: 6), child: Pill('$unread', tone: Tone.coral)) : null),
        tile(Icons.settings_outlined, 'Settings', 'Appearance, server, data', () => go(const SettingsScreen())),
        const SizedBox(height: 8),
        Text('Emotion insights are a guide, not a diagnosis.', textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

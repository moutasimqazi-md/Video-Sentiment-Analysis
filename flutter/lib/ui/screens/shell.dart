import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth.dart';
import '../../core/models.dart';
import '../../core/share_intake.dart';
import '../../core/stores.dart';
import 'plans_screen.dart';
import '../shell_nav.dart';
import '../widgets/common.dart';
import 'analyze_screen.dart';
import 'family_screen.dart';
import 'home_screen.dart';
import 'feed_screen.dart';
import 'import_screen.dart';
import 'results_screen.dart';

/// The signed-in app: five tabs, a strip showing analyses that are still running, and a message when one finishes.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<Job>? _sub;
  late final ShareController _share;
  final _visited = <int>{0}; // tabs are built the first time they are opened, so Feed and Import don't load until needed

  @override
  void initState() {
    super.initState();
    final jobs = context.read<JobQueue>();
    final history = context.read<HistoryStore>();
    _share = context.read<ShareController>()..addListener(_onShared);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShared()); // a link that arrived before sign-in
    _sub = jobs.onDone.listen((job) {
      final entry = job.entryId == null ? null : history.byId(job.entryId!);
      if (!mounted) return;
      context.read<AuthController>().refresh();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('${job.title} is ready'),
          action: entry == null ? null : SnackBarAction(label: 'View', onPressed: () => openResult(context, entry)),
          duration: const Duration(seconds: 8),
        ));
    });
  }

  /// A link shared to NeuroLens from another app starts analysing straight away.
  Future<void> _onShared() async {
    if (!mounted) return;
    final problem = _share.takeProblem();
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
    final link = _share.take();
    if (link == null) return;
    final auth = context.read<AuthController>();
    final queue = context.read<JobQueue>();
    final profile = context.read<ProfilesStore>();
    final nav = context.read<ShellNav>();
    nav.go(ShellNav.analyze);
    final me = auth.me;
    if (me != null && me.remaining <= 0) {
      await showUpgradePrompt(context, "You have used this month's ${me.quota} analyses on the ${me.plan.name} plan.");
      return;
    }
    await queue.addLink(link, profileId: profile.active);
    if (!mounted) return;
    auth.refresh(); // the server counted it against the plan
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(profile.active == 'me' ? 'Analyzing the shared link…' : 'Analyzing the shared link for ${profile.nameOf(profile.active)}…')));
  }

  @override
  void dispose() {
    _share.removeListener(_onShared);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<ShellNav>();
    final active = context.select<JobQueue, int>((q) => q.active.length);
    _visited.add(nav.index);
    final pages = const [HomeScreen(), AnalyzeScreen(), ImportScreen(), FeedScreen(), FamilyScreen()];

    return Scaffold(
      body: IndexedStack(index: nav.index, children: [for (var i = 0; i < pages.length; i++) i == nav.index || _visited.contains(i) ? pages[i] : const SizedBox.shrink()]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (active > 0 && nav.index != ShellNav.analyze) _RunningStrip(count: active, onTap: () => nav.go(ShellNav.analyze)),
        NavigationBar(
          selectedIndex: nav.index,
          onDestinationSelected: nav.go,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
            NavigationDestination(icon: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.add_circle_outline)), selectedIcon: const Icon(Icons.add_circle), label: 'Analyze'),
            const NavigationDestination(icon: Icon(Icons.upload_file_outlined), selectedIcon: Icon(Icons.upload_file), label: 'Import'),
            const NavigationDestination(icon: Icon(Icons.visibility_outlined), selectedIcon: Icon(Icons.visibility), label: 'Feed'),
            const NavigationDestination(icon: Icon(Icons.family_restroom_outlined), selectedIcon: Icon(Icons.family_restroom), label: 'Family'),
          ],
        ),
      ]),
    );
  }
}

class _RunningStrip extends StatelessWidget {
  const _RunningStrip({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final job = context.watch<JobQueue>().active.firstOrNull;
    return Material(
      color: t.colorScheme.secondaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(width: 12),
            Expanded(child: Text(count == 1 ? '${job?.stage ?? 'Working'}…' : '$count analyses running…', style: TextStyle(fontWeight: FontWeight.w700, color: t.colorScheme.onSecondaryContainer))),
            Pill('View', tone: Tone.coral, icon: Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

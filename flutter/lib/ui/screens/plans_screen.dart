import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/account_models.dart';
import '../../core/api.dart';
import '../../core/auth.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Opens the plans screen (from the usage bar, a limit message, or More).
void openPlans(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlansScreen()));

/// Shown when a plan limit stops something: says what happened and offers the plans.
Future<void> showUpgradePrompt(BuildContext context, String message) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_outlined, size: 32),
        title: const Text('Upgrade your plan'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Not now')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              Navigator.pop(c);
              openPlans(context);
            },
            child: const Text('See plans'),
          ),
        ],
      ),
    );

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _yearly = false;
  String? _busy; // the plan being switched to
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _yearly = auth.me?.cycle == 'yearly';
    if (auth.plans.isEmpty) auth.loadPlans();
    auth.refresh();
  }

  Future<void> _choose(Plan plan) async {
    final auth = context.read<AuthController>();
    final me = auth.me!;
    if (plan.id == me.plan.id && (plan.free || me.cycle == (_yearly ? 'yearly' : 'monthly'))) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => _Confirm(plan: plan, yearly: _yearly, current: me.plan, demo: auth.paymentsDemo),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = plan.id;
      _error = null;
    });
    try {
      String? msg;
      if (plan.free) {
        await auth.cancelPlan();
        msg = 'You are on the Starter plan.';
      } else {
        msg = await auth.subscribe(plan.id, _yearly ? 'yearly' : 'monthly');
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(plan.free ? msg! : 'You are now on ${plan.name}. ${msg ?? ''}'.trim()), duration: const Duration(seconds: 6)));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final auth = context.watch<AuthController>();
    final me = auth.me;
    final plans = auth.plans;

    return Scaffold(
      appBar: AppBar(title: const Text('Plans')),
      body: me == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
              NlCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Your plan: ${me.plan.name}', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                    Pill('${me.remaining} left', tone: me.outOfAnalyses ? Tone.coral : Tone.green),
                  ]),
                  const SizedBox(height: 12),
                  ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: me.usedFraction, minHeight: 10)),
                  const SizedBox(height: 8),
                  Text('${me.used} of ${me.quota} analyses used this month · resets ${me.resetsOn}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  if (me.plan.children > 0) Text('${me.childrenUsed} of ${me.childrenAllowed} child profiles with monitoring', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ]),
              ),
              const SizedBox(height: 16),
              Center(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: false, label: Text('Monthly')), ButtonSegment(value: true, label: Text('Yearly · save 25%'))],
                  selected: {_yearly},
                  onSelectionChanged: (v) => setState(() => _yearly = v.first),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[ErrorNote(_error!), const SizedBox(height: 12)],
              if (plans.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              for (final p in plans) ...[
                _PlanCard(plan: p, yearly: _yearly, current: p.id == me.plan.id, busy: _busy == p.id, onChoose: _busy != null ? null : () => _choose(p)),
                const SizedBox(height: 14),
              ],
              if (auth.paymentsDemo)
                Text('Payments are in demo mode on this server: no card is needed and nothing is charged.', textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text('Emotion insights are a guide, not a diagnosis.', textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.yearly, required this.current, required this.busy, required this.onChoose});
  final Plan plan;
  final bool yearly, current, busy;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final price = plan.free ? 'Free' : '\$${yearly ? plan.yearly : plan.monthly}';
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: current ? t.colorScheme.primary : plan.featured ? t.colorScheme.primary.withValues(alpha: 0.5) : t.colorScheme.outlineVariant, width: current || plan.featured ? 2 : 1)),
        child: NlCard(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plan.name, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(plan.blurb, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(price, style: t.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: 1)),
              if (!plan.free) Flexible(child: Padding(padding: const EdgeInsets.only(left: 6, bottom: 4), child: Text('/ month${yearly ? ', billed yearly' : ''}', style: t.textTheme.bodySmall))),
            ]),
            const SizedBox(height: 14),
            for (final f in plan.features) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check, size: 18, color: NlColors.green), const SizedBox(width: 8), Expanded(child: Text(f))])),
            for (final f in plan.off) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.close, size: 18, color: t.colorScheme.onSurfaceVariant), const SizedBox(width: 8), Expanded(child: Text(f, style: TextStyle(color: t.colorScheme.onSurfaceVariant)))])),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: current
                  ? OutlinedButton(onPressed: null, child: const Text('Your current plan'))
                  : FilledButton(onPressed: onChoose, child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : Text(plan.free ? 'Switch to Starter' : 'Choose ${plan.name}')),
            ),
          ]),
        ),
      ),
      if (plan.featured && !current) Positioned(top: -10, right: 18, child: const Pill('Most popular', tone: Tone.coral)),
    ]);
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({required this.plan, required this.yearly, required this.current, required this.demo});
  final Plan plan, current;
  final bool yearly, demo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final down = plan.free || plan.quota < current.quota;
    final monthly = yearly ? plan.yearly : plan.monthly;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 4, 22, 22 + MediaQuery.of(context).viewPadding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(plan.free ? 'Switch to Starter?' : 'Start ${plan.name}', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (!plan.free) Text('\$$monthly per month${yearly ? ' (\$${monthly * 12} billed yearly)' : ''}', style: t.textTheme.titleMedium),
        const SizedBox(height: 10),
        Text('${plan.quota} analyses a month · ${plan.children == 0 ? 'no child profiles' : '${plan.children} child profiles'}'),
        if (down) ...[
          const SizedBox(height: 10),
          Text(plan.children < current.children ? 'Child monitoring beyond what this plan includes is paused. Your analyses stay saved up to ${plan.history}.' : 'You keep your saved results, up to ${plan.history} analyses.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
        if (demo && !plan.free) ...[
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)), child: Text('Demo mode: this server does not take payments, so the plan switches on without a charge.', style: TextStyle(color: t.colorScheme.onSecondaryContainer))),
        ],
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(plan.free ? 'Switch to Starter' : 'Start plan')),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      ]),
    );
  }
}

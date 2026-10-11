import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alerts.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/moods.dart';
import '../../core/stores.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tab_bar.dart';
import 'instagram_signin.dart';
import 'results_screen.dart';
import 'plans_screen.dart';

const _kinds = [
  ('explore', 'Explore', 'What Instagram suggests to this account', Icons.explore_outlined),
  ('foryou', 'For You reels', 'The reels feed, scrolled a few times', Icons.movie_outlined),
  ('terms', 'Search topics', 'Top posts for topics you enter', Icons.search),
  ('profile', 'Account review', "How the account's own posts come across", Icons.insights_outlined),
];

/// Feed check: sign in to Instagram privately, check what a feed is showing, review an account, and (for a child) set up monitoring.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.profileId});
  final String? profileId;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late String _pid = widget.profileId ?? 'me';
  Map<String, dynamic> _session = const {};
  MonitorSettings? _monitor;
  List<ScanReport> _past = const [];
  List<AlertItem> _alerts = const [];
  ScanReport? _report;
  String _kind = 'explore';
  int _limit = 10;
  final _terms = TextEditingController();
  bool _consent = false, _monOn = false, _loading = true, _running = false;
  int _every = 120;
  String? _error;
  String _stage = '';
  double _progress = 0;
  Timer? _timer;

  bool get _child => _pid != 'me';
  bool get _connected => _session['connected'] != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _terms.dispose();
    super.dispose();
  }

  ApiClient get _api => context.read<ApiClient>();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _session = await _api.session(_pid);
      final mons = await _api.monitors();
      _monitor = mons.where((m) => m.profileId == _pid).firstOrNull;
      _past = await _api.scans(_pid);
      _alerts = _child ? (await _api.alerts(profile: _pid, limit: 10)).alerts : const [];
      _consent = _monitor?.consent ?? false;
      _monOn = _monitor?.enabled ?? false;
      _every = _monitor?.intervalMin ?? 120;
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _signIn() async {
    final profiles = context.read<ProfilesStore>();
    try {
      if (_child && !(_monitor?.consent ?? false)) {
        _monitor = await _api.saveMonitor(_pid, name: profiles.nameOf(_pid), enabled: false, intervalMin: _every, consent: true); // record that the child knows first
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      if (e.planLimit && mounted) showUpgradePrompt(context, e.message);
      return;
    }
    if (!mounted) return;
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => InstagramSignInScreen(profileId: _pid)));
    if (ok == true) await _load();
  }

  Future<void> _saveMonitor() async {
    try {
      _monitor = await _api.saveMonitor(_pid, name: context.read<ProfilesStore>().nameOf(_pid), enabled: _monOn && _consent, intervalMin: _every, consent: _consent);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monitoring settings saved')));
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      if (e.planLimit && mounted) showUpgradePrompt(context, e.message);
    }
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _running = true;
      _report = null;
      _stage = 'Starting';
      _progress = 0;
    });
    try {
      if (_child && !_consent) throw ApiException('Tick the confirmation that your child knows, and save, first.');
      final terms = _terms.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final id = await _api.startScan(_pid, _kind, terms: terms, limit: _limit);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll(id));
      _poll(id);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _running = false;
      });
      if (e.planLimit && mounted) showUpgradePrompt(context, e.message);
    }
  }

  Future<void> _poll(String id) async {
    try {
      final s = await _api.scan(id);
      if (!mounted) return;
      if (s.running) {
        setState(() {
          _stage = s.stage;
          _progress = s.progress;
        });
        return;
      }
      _timer?.cancel();
      setState(() {
        _running = false;
        if (s.status == 'error') {
          _error = s.error ?? "The check couldn't finish.";
        } else {
          _report = s;
        }
      });
      _load();
      context.read<AlertsController>().refresh();
    } on ApiException catch (e) {
      if (e.status == 404) {
        _timer?.cancel();
        if (mounted) {
          setState(() {
            _running = false;
            _error = 'That check is no longer available.';
          });
        }
      }
    }
  }

  Future<void> _openPast(ScanReport s) async {
    try {
      final full = await _api.scan(s.id);
      if (mounted) setState(() => _report = full);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final profiles = context.watch<ProfilesStore>();

    return Scaffold(
      appBar: const NlTabBar(title: 'Feed check'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
          Text('Sign in once, privately. NeuroLens checks what an account is being served and writes a short report.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          // ---- who
          NlCard(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _pid,
              decoration: const InputDecoration(labelText: 'Whose account?', prefixIcon: Icon(Icons.person_outline)),
              items: [const DropdownMenuItem(value: 'me', child: Text('Me')), for (final c in profiles.children) DropdownMenuItem(value: c.id, child: Text('${c.name} (child)'))],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _pid = v;
                  _report = null;
                });
                _load();
              },
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[ErrorNote(_error!), const SizedBox(height: 14)],
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else ...[
            // ---- child consent + monitoring
            if (_child) ...[
              NlCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Monitoring'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _consent,
                    onChanged: (v) => setState(() {
                      _consent = v ?? false;
                      if (!_consent) _monOn = false;
                    }),
                    title: Text("${profiles.nameOf(_pid)} knows I check what their Instagram shows. I'll talk with them about it."),
                  ),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _monOn, onChanged: _consent ? (v) => setState(() => _monOn = v) : null, title: const Text('Check automatically and alert me')),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: const [30, 60, 120, 360, 1440].contains(_every) ? _every : 120,
                    decoration: const InputDecoration(labelText: 'How often'),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('Every 30 minutes')),
                      DropdownMenuItem(value: 60, child: Text('Every hour')),
                      DropdownMenuItem(value: 120, child: Text('Every 2 hours')),
                      DropdownMenuItem(value: 360, child: Text('Every 6 hours')),
                      DropdownMenuItem(value: 1440, child: Text('Once a day')),
                    ],
                    onChanged: (v) => setState(() => _every = v ?? 120),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    if (_monitor?.enabled == true && _monitor?.connected == true) const Pill('Monitoring on', tone: Tone.green),
                    const Spacer(),
                    OutlinedButton(onPressed: _saveMonitor, child: const Text('Save settings')),
                  ]),
                  if (_monitor?.status == 'needs_login') const Padding(padding: EdgeInsets.only(top: 10), child: Text('The session expired. Sign in again to resume checks.')),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            // ---- sign in / connected
            NlCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: _connected ? NlColors.green : t.colorScheme.onSurfaceVariant, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_connected ? 'Instagram connected' : 'Not connected', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  if (_connected)
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(title: const Text('Disconnect Instagram?'), content: const Text('The saved session is deleted from the server. Automatic checks stop.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Disconnect'))]),
                        );
                        if (ok == true) {
                          await _api.disconnect(_pid);
                          _load();
                        }
                      },
                      child: const Text('Disconnect'),
                    ),
                ]),
                if (!_connected) ...[
                  const SizedBox(height: 8),
                  const _Tick("Instagram's own sign-in page opens inside the app."),
                  const _Tick('You type your login straight into Instagram. NeuroLens never sees your password.'),
                  const _Tick('Once you are in, the sign-in session is kept on the NeuroLens server so checks can run. Disconnect any time to delete it.'),
                  const SizedBox(height: 14),
                  FilledButton.icon(onPressed: (_child && !_consent) ? null : _signIn, icon: const Icon(Icons.lock_open), label: const Text('Sign in to Instagram')),
                  if (_child && !_consent) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Tick the confirmation above first.', style: t.textTheme.bodySmall)),
                ],
              ]),
            ),
            const SizedBox(height: 14),

            // ---- run a check
            if (_connected) ...[
              NlCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('What should we check?'),
                  for (final k in _kinds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _running ? null : () => setState(() => _kind = k.$1),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _kind == k.$1 ? t.colorScheme.primary : t.colorScheme.outlineVariant, width: _kind == k.$1 ? 2 : 1),
                            color: _kind == k.$1 ? t.colorScheme.secondaryContainer : null,
                          ),
                          child: Row(children: [
                            Icon(k.$4, color: t.colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k.$2, style: const TextStyle(fontWeight: FontWeight.w800)), Text(k.$3, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))])),
                            if (_kind == k.$1) Icon(Icons.check_circle, color: t.colorScheme.primary),
                          ]),
                        ),
                      ),
                    ),
                  if (_kind == 'terms') ...[const SizedBox(height: 4), TextField(controller: _terms, decoration: const InputDecoration(labelText: 'Topics (comma separated, up to 5)', hintText: 'fitness, cooking, travel'))],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _limit,
                    decoration: const InputDecoration(labelText: 'How many items'),
                    items: const [DropdownMenuItem(value: 6, child: Text('6 (quick)')), DropdownMenuItem(value: 10, child: Text('10')), DropdownMenuItem(value: 16, child: Text('16')), DropdownMenuItem(value: 24, child: Text('24'))],
                    onChanged: (v) => setState(() => _limit = v ?? 10),
                  ),
                  const SizedBox(height: 10),
                  Text("This shows what Instagram serves the account, not what was actually watched. Scrolling For You counts as viewing those reels, so it can nudge that account's recommendations.", style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  if (_running) ...[
                    ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 8)),
                    const SizedBox(height: 8),
                    Text(_stage, style: t.textTheme.bodySmall),
                  ] else
                    FilledButton.icon(onPressed: _run, icon: const Icon(Icons.play_arrow), label: const Text('Run check')),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            if (_report != null) ...[_ReportCard(report: _report!), const SizedBox(height: 14)],

            if (_alerts.isNotEmpty) ...[
              NlCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Recent alerts'),
                  for (final a in _alerts.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(a.level == 'high' ? Icons.error_outline : a.level == 'watch' ? Icons.visibility_outlined : Icons.check_circle_outline, color: a.level == 'high' ? t.colorScheme.primary : null),
                      title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(a.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: a.jobId == null ? null : () => openRemoteResult(context, a.jobId!),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            if (_past.isNotEmpty)
              NlCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Earlier checks'),
                  for (final s in _past.take(8))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_kinds.firstWhere((k) => k.$1 == s.kind, orElse: () => _kinds.first).$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${_date(s.createdAt)} · ${s.status == 'done' ? '${s.analyzed} checked' : s.status == 'running' ? 'running' : "didn't finish"}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: s.status == 'done' ? () => _openPast(s) : null,
                    ),
                ]),
              ),
          ],
        ]),
      ),
    );
  }

  static String _date(double ts) {
    final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }
}

class _Tick extends StatelessWidget {
  const _Tick(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check, size: 18, color: NlColors.green), const SizedBox(width: 8), Expanded(child: Text(text))]),
      );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});
  final ScanReport report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final api = context.read<ApiClient>();
    final ok = report.items.where((i) => i.ok).toList();
    final failed = report.items.length - ok.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      NlCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('${_kinds.firstWhere((k) => k.$1 == report.kind, orElse: () => _kinds.first).$2} report', subtitle: report.username == null ? null : '@${report.username}'),
          Row(children: [
            Ring(fraction: report.items.isEmpty ? 0 : report.analyzed / report.items.length, center: '${report.analyzed}', sub: 'checked', size: 92),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final l in report.lines.isEmpty ? ['Nothing could be analyzed in this check.'] : report.lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(l)),
            ])),
          ]),
          if (report.review.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Account review', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final r in report.review) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $r')),
              ]),
            ),
          ],
          if (report.moodMix.isNotEmpty) ...[const SizedBox(height: 12), MoodBars(entries: [for (final m in report.moodMix.take(6)) MapEntry(m.key, m.value.toDouble())])],
        ]),
      ),
      if (ok.isNotEmpty) ...[
        const SizedBox(height: 14),
        const SectionTitle('What was checked'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.72,
          children: [
            for (final i in ok)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => openRemoteResult(context, i.jobId!),
                child: NlCard(
                  padding: EdgeInsets.zero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(18)), child: SizedBox(width: double.infinity, child: NetThumb(url: api.thumbnailUrl(i.jobId!), emoji: moodEmoji(i.mood), aspect: 1, radius: 0)))),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${moodEmoji(i.mood)} ${cap(i.mood ?? '')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          Pill(switch (i.level) { 'high' => 'High concern', 'watch' => 'Worth a look', _ => 'Calm' }, tone: switch (i.level) { 'high' => Tone.coral, 'watch' => Tone.amber, _ => Tone.green }),
                          if (i.safety == 'review') const Pill('Revealing?', tone: Tone.amber),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
        ),
        if (failed > 0) Padding(padding: const EdgeInsets.only(top: 10), child: Text("$failed ${failed == 1 ? 'item' : 'items'} couldn't be checked (private or removed).", style: t.textTheme.bodySmall)),
      ],
    ]);
  }
}

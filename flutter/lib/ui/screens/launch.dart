import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../theme.dart';
import 'signed_in_gate.dart';

/// Opening sequence: the animated splash (which also checks the server and restores the saved sign-in), then the app.
class Launcher extends StatefulWidget {
  const Launcher({super.key, this.splashTime = const Duration(milliseconds: 1900)});
  final Duration splashTime; // tests shorten this
  @override
  State<Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<Launcher> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      child: _splashDone ? const SignedInGate(key: ValueKey('gate')) : SplashScreen(key: const ValueKey('splash'), minTime: widget.splashTime, onDone: () => setState(() => _splashDone = true)),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone, this.minTime = const Duration(milliseconds: 1900)});
  final VoidCallback onDone;
  final Duration minTime;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..forward();
  bool _checking = true;
  bool _unreachable = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _checking = true;
      _unreachable = false;
    });
    final ping = context.read<ApiClient>().ping();
    final auth = context.read<AuthController>();
    final restore = auth.restore(); // checks the saved sign-in with the server
    await Future<void>.delayed(widget.minTime); // the splash always shows for a moment
    final reachable = await ping;
    await restore;
    if (!mounted || _gone) return;
    if (reachable || auth.signedIn) { // signed in offline still opens: saved results work without the server
      _gone = true;
      widget.onDone();
    } else {
      setState(() {
        _checking = false;
        _unreachable = true;
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _continueAnyway() {
    _gone = true;
    widget.onDone(); // history and saved results still work without the server
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final logoScale = CurvedAnimation(parent: _c, curve: const Interval(0, 0.6, curve: Curves.easeOutBack));
    final fadeText = CurvedAnimation(parent: _c, curve: const Interval(0.45, 1, curve: Curves.easeOut));

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark ? const [Color(0xFF1C1A2A), Color(0xFF0E1322)] : const [Color(0xFFFFF4F1), Color(0xFFF2F5FF)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            const Spacer(flex: 3),
            ScaleTransition(
              scale: Tween(begin: 0.6, end: 1.0).animate(logoScale),
              child: FadeTransition(
                opacity: _c.drive(CurveTween(curve: const Interval(0, 0.4))),
                child: Container(
                  width: 112,
                  height: 112,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(color: t.colorScheme.surface, borderRadius: BorderRadius.circular(34), boxShadow: [BoxShadow(color: NlColors.coral.withValues(alpha: 0.28), blurRadius: 40, offset: const Offset(0, 16))]),
                  child: Image.asset('assets/logo.png'),
                ),
              ),
            ),
            const SizedBox(height: 26),
            FadeTransition(
              opacity: fadeText,
              child: Column(children: [
                Text.rich(TextSpan(children: [const TextSpan(text: 'Neuro'), TextSpan(text: 'Lens', style: TextStyle(color: t.colorScheme.primary))]), style: t.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                const SizedBox(height: 8),
                Text('Know what a Reel makes people feel', style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
            const Spacer(flex: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120),
              child: _unreachable
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(children: [
                        Text("Can't reach NeuroLens right now.", style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Check your connection. You can still open your saved results.', textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 10),
                        Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 8, children: [
                          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: _start, child: const Text('Try again')),
                          OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: _continueAnyway, child: const Text('Continue')),
                        ]),
                      ]),
                    )
                  : _checking
                      ? FadeTransition(opacity: fadeText, child: Column(children: [const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)), const SizedBox(height: 10), Text('Connecting…', style: t.textTheme.bodySmall)]))
                      : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide(this.icon, this.emoji, this.title, this.text);
  final IconData icon;
  final String emoji;
  final String title, text;
}

const _slides = [
  _Slide(Icons.auto_awesome, '🎬', 'Know what a Reel makes people feel', 'Paste a link or pick a video or image. NeuroLens reads the visuals and sound, and tells you the mood, with the frames that shaped it.'),
  _Slide(Icons.family_restroom, '👨‍👩‍👧', 'Look after what your family watches', 'Add a child profile, review the Reels they watch, and see a weekly wellbeing summary.'),
  _Slide(Icons.visibility_outlined, '🔒', 'Check a feed, privately', 'Sign in to Instagram inside a private browser, check what an account is being shown, and get alerts when something needs a look.'),
];

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _page = PageController();
  int _i = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final last = _i == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.fromLTRB(8, 8, 12, 0), child: TextButton(onPressed: widget.onDone, child: const Text('Skip')))),
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: _slides.length,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (context, i) {
                final s = _slides[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 170,
                      height: 170,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(52)),
                      child: Text(s.emoji, style: const TextStyle(fontSize: 76)),
                    ),
                    const SizedBox(height: 36),
                    Text(s.title, textAlign: TextAlign.center, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
                    const SizedBox(height: 14),
                    Text(s.text, textAlign: TextAlign.center, style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4)),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var d = 0; d < _slides.length; d++)
              AnimatedContainer(duration: const Duration(milliseconds: 250), margin: const EdgeInsets.symmetric(horizontal: 4), width: d == _i ? 26 : 8, height: 8, decoration: BoxDecoration(color: d == _i ? t.colorScheme.primary : t.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(99))),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => last ? widget.onDone() : _page.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
                child: Text(last ? 'Get started' : 'Next'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

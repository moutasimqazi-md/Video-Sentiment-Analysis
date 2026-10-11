import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth.dart';
import '../../core/settings.dart';
import 'auth_screen.dart';
import 'launch.dart';
import 'shell.dart';

/// Decides what to show: the sign-in screen, the short intro (once, for a new account), or the app.
class SignedInGate extends StatefulWidget {
  const SignedInGate({super.key});

  @override
  State<SignedInGate> createState() => _SignedInGateState();
}

class _SignedInGateState extends State<SignedInGate> {
  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    if (auth.status == AuthStatus.starting) auth.restore(); // when the app starts without the splash (tests)
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final settings = context.watch<AppSettings>();
    final Widget child;
    if (auth.status == AuthStatus.starting) {
      child = const Scaffold(key: ValueKey('loading'), body: Center(child: CircularProgressIndicator()));
    } else if (!auth.signedIn) {
      child = const AuthScreen(key: ValueKey('auth'));
    } else if (!settings.introSeen) {
      child = IntroScreen(key: const ValueKey('intro'), onDone: settings.setIntroSeen);
    } else {
      child = const AppShell(key: ValueKey('app'));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: child);
  }
}

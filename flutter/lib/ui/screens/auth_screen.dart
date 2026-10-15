import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';

final _emailRe = RegExp(r'^[^@\s]{1,64}@[^@\s]{1,255}\.[^@\s]{2,}$');

/// Sign in or create an account: the first thing a signed-out person sees.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.startOnSignUp = false});
  final bool startOnSignUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _signUp = widget.startOnSignUp;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _show = false, _agree = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (_signUp && !_agree) {
      setState(() => _error = 'Please agree to the Terms and Privacy Policy to create an account.');
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthController>();
    try {
      if (_signUp) {
        await auth.signup(name: _name.text, email: _email.text, password: _password.text);
      } else {
        await auth.login(email: _email.text, password: _password.text);
      }
      // the gate switches to the app by itself once the account is signed in
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String path) async {
    final base = context.read<AppSettings>().baseUrl;
    await launchUrl(Uri.parse('$base/pages/$path'), mode: LaunchMode.externalApplication);
  }

  void _forgot() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Forgot your password?'),
        content: const Text("Password reset by email isn't set up on this server yet. Ask the person who runs your NeuroLens server to reset it, or create a new account with a different email."),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final notice = context.watch<AuthController>().notice;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: dark ? const [Color(0xFF1C1A2A), Color(0xFF0E1322)] : const [Color(0xFFFFF4F1), Color(0xFFF2F5FF)])),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Image.asset('assets/logo.png', width: 44, height: 44),
                        const SizedBox(width: 10),
                        Text.rich(TextSpan(children: [const TextSpan(text: 'Neuro'), TextSpan(text: 'Lens', style: TextStyle(color: t.colorScheme.primary))]), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 26),
                      Text(_signUp ? 'Create your account' : 'Welcome back', textAlign: TextAlign.center, style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
                      const SizedBox(height: 8),
                      Text(_signUp ? 'Analyze videos, look after your family, and keep your results on every device.' : 'Sign in to pick up where you left off.', textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 22),
                      NlCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [ButtonSegment(value: false, label: Text('Sign in')), ButtonSegment(value: true, label: Text('Create account'))],
                            selected: {_signUp},
                            onSelectionChanged: (v) => setState(() {
                              _signUp = v.first;
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: 18),
                          if (notice != null && !_signUp) ...[ErrorNote(notice), const SizedBox(height: 14)],
                          if (_signUp) ...[
                            TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.name],
                              decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
                              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name.' : null,
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                            validator: (v) => _emailRe.hasMatch((v ?? '').trim()) ? null : 'Enter a valid email address.',
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: !_show,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              helperText: _signUp ? 'At least 8 characters' : null,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(tooltip: _show ? 'Hide password' : 'Show password', icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _show = !_show)),
                            ),
                            validator: (v) => _signUp ? ((v ?? '').length < 8 ? 'Use at least 8 characters.' : null) : ((v ?? '').isEmpty ? 'Enter your password.' : null),
                          ),
                          if (!_signUp)
                            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgot, child: const Text('Forgot password?'))),
                          if (_signUp) ...[
                            const SizedBox(height: 6),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _agree,
                              onChanged: (v) => setState(() => _agree = v ?? false),
                              title: Text.rich(TextSpan(style: t.textTheme.bodySmall, children: [
                                const TextSpan(text: 'I agree to the '),
                                WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: InkWell(onTap: () => _open('terms.html'), child: Text('Terms', style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 12)))),
                                const TextSpan(text: ' and '),
                                WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: InkWell(onTap: () => _open('privacy.html'), child: Text('Privacy Policy', style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 12)))),
                              ])),
                            ),
                          ],
                          if (_error != null) ...[const SizedBox(height: 10), ErrorNote(_error!)],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(_signUp ? 'Create account' : 'Sign in'),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(_signUp ? 'Already have an account?' : "New to NeuroLens?", style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                        TextButton(onPressed: () => setState(() {
                              _signUp = !_signUp;
                              _error = null;
                            }), child: Text(_signUp ? 'Sign in' : 'Create an account')),
                      ]),
                      const SizedBox(height: 4),
                      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                        const Icon(Icons.lock_outline, size: 14, color: NlColors.green),
                        Text('Your password is stored securely and never leaves the server unhashed.', textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

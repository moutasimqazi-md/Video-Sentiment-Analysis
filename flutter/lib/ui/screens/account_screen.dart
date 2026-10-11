import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../widgets/common.dart';
import 'plans_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _rename(BuildContext context) async {
    final auth = context.read<AuthController>();
    final c = TextEditingController(text: auth.me?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      try {
        await auth.rename(c.text.trim());
      } on ApiException catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final auth = context.read<AuthController>();
    final cur = TextEditingController(), next = TextEditingController();
    String? error;
    bool busy = false;
    final done = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Change password'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 12),
            TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: ErrorNote(error!)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      set(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await auth.changePassword(cur.text, next.text);
                        if (d.mounted) Navigator.pop(d, true);
                      } on ApiException catch (e) {
                        set(() {
                          busy = false;
                          error = e.message;
                        });
                      }
                    },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    if (done == true && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed. Your other devices were signed out.')));
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(title: const Text('Sign out?'), content: const Text('Your results stay saved on this phone for when you sign back in.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sign out'))]),
    );
    if (ok == true && context.mounted) {
      final auth = context.read<AuthController>();
      Navigator.of(context).popUntil((r) => r.isFirst);
      await auth.logout();
    }
  }

  Future<void> _delete(BuildContext context) async {
    final auth = context.read<AuthController>();
    final pw = TextEditingController();
    String? error;
    bool busy = false;
    final done = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, size: 32),
          title: const Text('Delete your account?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This permanently deletes your account, your subscription, your child monitoring and alerts, and any Instagram sessions stored for you on the server. Saved results on this phone are removed too. This cannot be undone.'),
            const SizedBox(height: 14),
            TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Enter your password to confirm')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: ErrorNote(error!)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      set(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await auth.deleteAccount(pw.text);
                        if (d.mounted) Navigator.pop(d, true);
                      } on ApiException catch (e) {
                        set(() {
                          busy = false;
                          error = e.message;
                        });
                      }
                    },
              child: Text('Delete account', style: TextStyle(color: Theme.of(d).colorScheme.primary)),
            ),
          ],
        ),
      ),
    );
    if (done == true && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final auth = context.watch<AuthController>();
    final me = auth.me;
    if (me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        NlCard(
          child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: t.colorScheme.secondaryContainer, child: Text(me.displayName.isEmpty ? '?' : me.displayName[0].toUpperCase(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: t.colorScheme.primary))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me.displayName, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(me.email ?? '', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ])),
            IconButton(tooltip: 'Edit name', icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(context)),
          ]),
        ),
        if (auth.offline) ...[const SizedBox(height: 12), const ErrorNote("You're offline, so this may be out of date.")],
        const SizedBox(height: 14),
        NlCard(
          onTap: () => openPlans(context),
          child: Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.workspace_premium_outlined, color: t.colorScheme.primary)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${me.plan.name} plan', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text('${me.used} of ${me.quota} analyses used · resets ${me.resetsOn}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ])),
            const Icon(Icons.chevron_right),
          ]),
        ),
        const SizedBox(height: 14),
        NlCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(leading: const Icon(Icons.password_outlined), title: const Text('Change password'), trailing: const Icon(Icons.chevron_right), onTap: () => _changePassword(context)),
            const Divider(),
            ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), onTap: () => _signOut(context)),
          ]),
        ),
        const SizedBox(height: 14),
        NlCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('Your data'),
            Text('Saved results and child profiles live on this phone. Your account, plan and Feed check sessions are stored on the server, and are only visible to you.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => _delete(context), icon: Icon(Icons.delete_forever_outlined, color: t.colorScheme.primary), label: Text('Delete my account', style: TextStyle(color: t.colorScheme.primary))),
          ]),
        ),
      ]),
    );
  }
}

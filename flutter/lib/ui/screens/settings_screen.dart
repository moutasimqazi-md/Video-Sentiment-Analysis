import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/stores.dart';
import '../widgets/common.dart';
import 'setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = context.watch<AppSettings>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        NlCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('Appearance'),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => s.setTheme(v.first),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        NlCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('Your data'),
            Text('Saved results and child profiles are stored on this phone, for the account you are signed in to.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(title: const Text('Delete all saved results?'), content: const Text('Every saved analysis is removed from this phone.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]),
                );
                if (ok == true && context.mounted) {
                  await context.read<HistoryStore>().clear();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved results deleted')));
                }
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete saved results'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        NlCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('Advanced'),
            Text(s.isCustomServer ? s.baseUrl : 'Using the built-in NeuroLens server.', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetupScreen(initial: s.isCustomServer ? s.baseUrl : ''))),
              icon: const Icon(Icons.dns_outlined, size: 18),
              label: const Text('Server address'),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Center(child: Text('NeuroLens 1.0 · Emotion insights are a guide, not a diagnosis.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center)),
      ]),
    );
  }
}

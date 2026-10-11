import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/settings.dart';
import '../widgets/common.dart';

/// First launch: tell the app where the NeuroLens server is.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.initial, this.advanced = true});
  final String? initial;
  final bool advanced; // opened from Settings

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _c = TextEditingController(text: widget.initial ?? '');
  bool _testing = false;
  String? _error;
  bool _ok = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final settings = context.read<AppSettings>();
    final normalized = AppSettings.normalizeUrl(_c.text);
    if (normalized.isEmpty) {
      setState(() => _error = 'Enter the address of your NeuroLens server.');
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
      _ok = false;
    });
    final reachable = await context.read<ApiClient>().probe(normalized);
    if (!mounted) return;
    if (reachable) {
      await settings.setBaseUrl(normalized);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _ok = true;
      });
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _testing = false;
        _error = "Couldn't reach a NeuroLens server at that address. Check it and that the server is running.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Server address')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Use a different server', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('NeuroLens connects to its own server automatically. Only change this to use a server of your own, for example one on your Wi-Fi.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 22),
                TextField(
                  controller: _c,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _connect(),
                  decoration: const InputDecoration(labelText: 'Server address', hintText: AppSettings.defaultServer, prefixIcon: Icon(Icons.link)),
                ),
                const SizedBox(height: 10),
                Text('Use your public address (for example the ngrok one), or your computer\'s address on your Wi-Fi such as 192.168.1.20:8000. On an Android emulator use 10.0.2.2:8000.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                if (_error != null) ...[const SizedBox(height: 14), ErrorNote(_error!)],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _testing ? null : _connect,
                  child: _testing ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(_ok ? 'Connected' : 'Save and connect'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () async {
                    await context.read<AppSettings>().useDefaultServer();
                    if (context.mounted) Navigator.of(context).pop(true);
                  },
                  child: const Text('Use the built-in server'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

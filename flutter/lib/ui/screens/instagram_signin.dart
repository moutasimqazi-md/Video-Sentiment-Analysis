import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_cookie_manager_plus/webview_cookie_manager_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api.dart';

/// Instagram's own sign-in page, shown inside the app on this phone. The password is typed into Instagram, never into NeuroLens;
/// once Instagram says you're signed in, the session is handed to the server so feed checks can run there.
class InstagramSignInScreen extends StatefulWidget {
  const InstagramSignInScreen({super.key, required this.profileId});
  final String profileId;

  @override
  State<InstagramSignInScreen> createState() => _InstagramSignInScreenState();
}

class _InstagramSignInScreenState extends State<InstagramSignInScreen> {
  static const _home = 'https://www.instagram.com/';
  final _cookies = WebviewCookieManager();
  late final WebViewController _web;
  bool _sending = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() => _loading = true); },
        onPageFinished: (url) { if (mounted) setState(() => _loading = false); _check(url); },
        onUrlChange: (c) => _check(c.url ?? ''),
      ))
      ..loadRequest(Uri.parse('${_home}accounts/login/'));
  }

  Future<void> _check(String url) async {
    if (_sending || !url.startsWith(_home)) return;
    if (url.contains('/challenge') || url.contains('/accounts/login') || url.contains('/accounts/suspended')) return; // still signing in, or a security step
    final cookies = await _cookies.getCookies(_home);
    if (!cookies.any((k) => k.name == 'sessionid' && k.value.isNotEmpty) || !mounted) return;
    final api = context.read<ApiClient>();
    setState(() { _sending = true; _error = null; });
    try {
      await api.importSession(widget.profileId, [
        for (final k in cookies) {'name': k.name, 'value': k.value, 'domain': '.instagram.com', 'path': '/', 'httpOnly': k.httpOnly, if (k.expires != null) 'expires': k.expires!.millisecondsSinceEpoch / 1000},
      ]);
      await _cookies.clearCookies(); // this phone doesn't keep the session; the next account starts clean
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() { _sending = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() { _sending = false; _error = "Couldn't reach the server. Check your connection and try again."; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in to Instagram'), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(false))),
      body: Stack(children: [
        WebViewWidget(controller: _web),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Positioned(left: 16, right: 16, bottom: 16, child: Material(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)))),
        if (_sending) Container(color: Colors.black54, alignment: Alignment.center, child: const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Connecting…', style: TextStyle(color: Colors.white))])),
      ]),
    );
  }
}

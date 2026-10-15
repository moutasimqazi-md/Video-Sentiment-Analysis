import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_cookie_manager_plus/webview_cookie_manager_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api.dart';
import '../../core/platforms.dart';

/// A site's own sign-in page, shown inside the app on this phone. The password is typed into the site, never into NeuroLens;
/// once the site says you're signed in, the session is handed to the server so feed checks can run there.
/// (Sites that refuse web-view sign-in, like YouTube, use the server's streamed private browser instead: see private_browser.dart.)
class SiteSignInScreen extends StatefulWidget {
  const SiteSignInScreen({super.key, required this.profileId, required this.site});
  final String profileId;
  final Site site;

  @override
  State<SiteSignInScreen> createState() => _SiteSignInScreenState();
}

class _SiteSignInScreenState extends State<SiteSignInScreen> {
  final _cookies = WebviewCookieManager();
  late final WebViewController _web;
  bool _sending = false;
  bool _loading = true;
  String? _error;

  Site get _site => widget.site;

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
      ..loadRequest(Uri.parse(_site.loginUrl));
  }

  Future<void> _check(String url) async {
    if (_sending || !url.startsWith(_site.home)) return;
    if (_site.isPending(url)) return; // still signing in, or a security step
    final cookies = await _cookies.getCookies(_site.home);
    if (!_site.signedIn([for (final k in cookies) if (k.value.isNotEmpty) k.name]) || !mounted) return;
    final api = context.read<ApiClient>();
    setState(() { _sending = true; _error = null; });
    try {
      await api.importSession(widget.profileId, [
        for (final k in cookies) {'name': k.name, 'value': k.value, 'domain': _site.cookieDomain, 'path': '/', 'httpOnly': k.httpOnly, if (k.expires != null) 'expires': k.expires!.millisecondsSinceEpoch ~/ 1000}
      ], platform: _site.code);
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
      appBar: AppBar(title: Text('Sign in to ${_site.name}'), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(false))),
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

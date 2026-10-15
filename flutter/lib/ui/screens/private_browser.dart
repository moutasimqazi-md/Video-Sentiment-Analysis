import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api.dart';
import '../../core/platforms.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The remote page's logical size; must match `VIEW_W`/`VIEW_H` in backend/neurolens/live.py.
const double kViewW = 440, kViewH = 780;

typedef SocketConnector = WebSocketChannel Function(Uri uri);

/// Drives the private browser (Instagram, YouTube, TikTok or Facebook) that the server streams as pictures. Nothing here ever sees the
/// password: taps and key presses go to the server's isolated browser, which sends the site the login.
class PrivateBrowserController extends ChangeNotifier {
  PrivateBrowserController({required this.api, required this.profileId, this.platform = 'ig', SocketConnector? connector}) : _connector = connector ?? WebSocketChannel.connect, host = '${siteOf(platform).name.toLowerCase()}.com';
  final ApiClient api;
  final String profileId, platform;
  final SocketConnector _connector;

  Uint8List? frame;
  String host;
  String? hint;
  String state = 'starting'; // starting | live | finishing | connected | closed | error
  String? error;
  bool _closing = false;
  int _attempts = 0;
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  DateTime _lastMove = DateTime.fromMillisecondsSinceEpoch(0);

  bool get done => state == 'connected' || state == 'closed' || state == 'error';

  Future<void> start() async {
    try {
      await api.startLogin(profileId, platform: platform);
      await _connect();
    } on ApiException catch (e) {
      _fail(e.message);
    }
  }

  Future<void> _connect() async {
    try {
      final token = await api.viewToken(profileId, platform: platform);
      _ch = _connector(api.viewSocket(profileId, token));
      _sub = _ch!.stream.listen(_onMessage, onError: (_) => _dropped(), onDone: _dropped);
    } on ApiException catch (e) {
      _fail(e.message);
    }
  }

  void _onMessage(dynamic m) {
    if (m is String) {
      final j = jsonDecode(m) as Map<String, dynamic>;
      switch (j['type']) {
        case 'url':
          host = (j['host'] as String?)?.isNotEmpty == true ? j['host'] as String : host;
        case 'hint':
          hint = (j['text'] as String?)?.isNotEmpty == true ? j['text'] as String : null;
        case 'state':
          state = j['state'] as String? ?? state;
          error = j['error'] as String?;
          if (done) _closing = true;
      }
    } else if (m is List<int>) {
      frame = m is Uint8List ? m : Uint8List.fromList(m);
      if (state == 'starting') state = 'live';
      _attempts = 0;
    }
    notifyListeners();
  }

  void _dropped() {
    if (_closing || done) return;
    if (++_attempts <= 3) {
      state = 'starting';
      notifyListeners();
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!_closing) _connect();
      });
    } else {
      _fail('The connection to the private browser was lost.');
    }
  }

  void _fail(String message) {
    state = 'error';
    error = message;
    _closing = true;
    notifyListeners();
  }

  void _send(Map<String, dynamic> m) => _ch?.sink.add(jsonEncode(m));

  void tapDown(double x, double y) => _send({'t': 'mouse', 'type': 'down', 'x': x, 'y': y, 'button': 'left', 'clicks': 1});
  void tapUp(double x, double y) => _send({'t': 'mouse', 'type': 'up', 'x': x, 'y': y, 'button': 'left', 'clicks': 1});

  void move(double x, double y) {
    final now = DateTime.now();
    if (now.difference(_lastMove).inMilliseconds < 40) return;
    _lastMove = now;
    _send({'t': 'mouse', 'type': 'move', 'x': x, 'y': y});
  }

  void scroll(double x, double y, double dy) => _send({'t': 'mouse', 'type': 'wheel', 'x': x, 'y': y, 'dx': 0, 'dy': dy});
  void text(String s) => _send({'t': 'text', 'text': s});
  void key(String k) => _send({'t': 'key', 'key': k});

  Future<void> cancel() async {
    _closing = true;
    try {
      await api.cancelLogin(profileId, platform: platform);
    } catch (_) {}
    await _teardown();
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    await _ch?.sink.close();
    _sub = null;
    _ch = null;
  }

  @override
  void dispose() {
    _closing = true;
    _teardown();
    super.dispose();
  }
}

/// Full-screen sign-in. Pops with `true` once the site is connected.
class PrivateBrowserScreen extends StatefulWidget {
  const PrivateBrowserScreen({super.key, required this.profileId, this.platform = 'ig', this.connector});
  final String profileId, platform;
  final SocketConnector? connector;

  @override
  State<PrivateBrowserScreen> createState() => _PrivateBrowserScreenState();
}

class _PrivateBrowserScreenState extends State<PrivateBrowserScreen> {
  late final PrivateBrowserController _c;
  final _focus = FocusNode();
  final _keys = TextEditingController(text: _sentinel);
  static const _sentinel = '​'; // lets a soft keyboard report Backspace even when the field is empty
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _c = PrivateBrowserController(api: context.read<ApiClient>(), profileId: widget.profileId, platform: widget.platform, connector: widget.connector)..addListener(_onChange);
    _c.start();
  }

  Future<void> _onChange() async {
    if (_c.state == 'connected' && !_popped) {
      _popped = true;
      try {
        await context.read<ApiClient>().markConnected(widget.profileId, platform: widget.platform);
      } catch (_) {}
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    _focus.dispose();
    _keys.dispose();
    super.dispose();
  }

  void _typed(String v) {
    if (v.isEmpty) {
      _c.key('Backspace');
    } else if (v != _sentinel) {
      final s = v.startsWith(_sentinel) ? v.substring(1) : v.replaceAll(_sentinel, '');
      if (s.isNotEmpty) _c.text(s);
    }
    _keys.value = const TextEditingValue(text: _sentinel, selection: TextSelection.collapsed(offset: 1));
  }

  Offset _logical(Offset local, Size size) => Offset((local.dx / size.width * kViewW).clamp(0, kViewW), (local.dy / size.height * kViewH).clamp(0, kViewH));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _c.cancel();
        if (context.mounted) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Sign in to ${siteOf(widget.platform).name}'),
          actions: [
            IconButton(tooltip: 'Show keyboard', icon: const Icon(Icons.keyboard_outlined), onPressed: () {
              _focus.requestFocus();
              SystemChannels.textInput.invokeMethod('TextInput.show');
            }),
            TextButton(onPressed: () async {
              await _c.cancel();
              if (context.mounted) Navigator.of(context).pop(false);
            }, child: const Text('Cancel')),
          ],
        ),
        body: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: t.colorScheme.surfaceContainerHighest,
              child: Row(children: [
                const Icon(Icons.lock, size: 15, color: NlColors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(_c.host, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                const Pill('Private browser', tone: Tone.green, icon: Icons.shield_outlined),
              ]),
            ),
            if (_c.hint != null) Container(width: double.infinity, padding: const EdgeInsets.all(12), color: t.brightness == Brightness.dark ? const Color(0xFF3A3020) : const Color(0xFFFFF4DE), child: Text(_c.hint!, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: kViewW / kViewH,
                  child: Stack(children: [
                    Positioned.fill(
                      child: LayoutBuilder(builder: (context, box) {
                        final size = Size(box.maxWidth, box.maxHeight);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) {
                            if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux) _focus.requestFocus();
                            final p = _logical(d.localPosition, size);
                            _c.tapDown(p.dx, p.dy);
                          },
                          onTapUp: (d) {
                            final p = _logical(d.localPosition, size);
                            _c.tapUp(p.dx, p.dy);
                          },
                          onTapCancel: () => _c.tapUp(0, 0),
                          onPanUpdate: (d) {
                            final p = _logical(d.localPosition, size);
                            _c.scroll(p.dx, p.dy, -d.delta.dy * (kViewH / size.height) * 1.4);
                          },
                          child: _c.frame == null ? const ColoredBox(color: Colors.white) : Image.memory(_c.frame!, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium, width: double.infinity, height: double.infinity),
                        );
                      }),
                    ),
                    // the keyboard sink: tiny and invisible, but a real text field so every platform's keyboard can type into it
                    Positioned(
                      left: 0,
                      bottom: 0,
                      width: 2,
                      height: 2,
                      child: Opacity(
                        opacity: 0.01,
                        child: TextField(
                          controller: _keys,
                          focusNode: _focus,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.go,
                          onChanged: _typed,
                          onSubmitted: (_) {
                            _c.key('Enter');
                            _focus.requestFocus();
                          },
                        ),
                      ),
                    ),
                    if (_c.state == 'starting' || _c.state == 'finishing')
                      Positioned.fill(child: ColoredBox(color: t.colorScheme.surface.withValues(alpha: 0.92), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 14),
                        Text(_c.state == 'finishing' ? 'Signed in. Saving your session…' : 'Starting the private browser…'),
                      ])))),
                    if (_c.state == 'closed' || _c.state == 'error')
                      Positioned.fill(child: ColoredBox(color: t.colorScheme.surface, child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ErrorNote(_c.error ?? 'The private browser closed before you signed in.'),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Back')),
                      ]))))),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.lock_outline, size: 16, color: NlColors.green),
                const SizedBox(width: 8),
                Expanded(child: Text('Type your username and password in the browser above. They go straight to ${siteOf(widget.platform).name}, and NeuroLens never sees them. Tap the keyboard button to type.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

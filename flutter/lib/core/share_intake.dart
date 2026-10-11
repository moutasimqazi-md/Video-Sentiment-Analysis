import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Pulls the first web link out of shared text ("Check this out https://youtu.be/abc from YouTube" -> the link).
String? extractLink(String? text) {
  if (text == null) return null;
  final m = RegExp(r'https?://[^\s<>"]+', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  return m.group(0)!.replaceFirst(RegExp(r'[).,;!?]+$'), '');
}

/// Links shared to NeuroLens from other apps (Instagram, YouTube, a browser). The share arrives even when nobody is signed in,
/// so the link waits here until the app can start the analysis.
class ShareController extends ChangeNotifier {
  ShareController({MethodChannel? channel}) : _ch = channel ?? const MethodChannel('neurolens/share');
  final MethodChannel _ch;

  String? _pending; // a link waiting to be analysed
  String? _problem; // a share that had no link in it
  String? get pendingLink => _pending;
  String? get problem => _problem;

  Future<void> start() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shared') _accept(call.arguments as String?);
    });
    try {
      _accept(await _ch.invokeMethod<String>('initial'));
    } on MissingPluginException {
      // not on a phone (tests, desktop)
    } on PlatformException {
      // nothing was shared
    }
  }

  void _accept(String? text) {
    if (text == null || text.trim().isEmpty) return;
    final link = extractLink(text);
    if (link == null) {
      _problem = "That share didn't contain a link. Share a Reel or video link to NeuroLens.";
    } else {
      _pending = link;
      _problem = null;
    }
    notifyListeners();
  }

  /// The waiting link, once; asking for it clears it.
  String? take() {
    final l = _pending;
    _pending = null;
    return l;
  }

  String? takeProblem() {
    final p = _problem;
    _problem = null;
    return p;
  }
}

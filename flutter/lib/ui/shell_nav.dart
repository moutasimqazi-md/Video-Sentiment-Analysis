import 'package:flutter/foundation.dart';

/// Which bottom tab is showing, so any screen can jump to another tab.
class ShellNav extends ChangeNotifier {
  int _index = 0;
  int get index => _index;

  static const home = 0, analyze = 1, import = 2, feed = 3, family = 4;

  void go(int i) {
    if (i == _index) return;
    _index = i;
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';
import 'window_service.dart';

/// Tracks whether the app UI is currently in "mini" (small, pinned,
/// always-on-top) mode or the normal full window, and drives the actual
/// OS window changes via [WindowService].
class WindowModeNotifier extends ChangeNotifier {
  bool _isMini = false;
  bool get isMini => _isMini;

  Future<void> enterMiniMode() async {
    if (_isMini) return;
    await WindowService.enterMiniMode();
    _isMini = true;
    notifyListeners();
  }

  Future<void> exitMiniMode() async {
    if (!_isMini) return;
    await WindowService.exitMiniMode();
    _isMini = false;
    notifyListeners();
  }

  Future<void> toggle() => _isMini ? exitMiniMode() : enterMiniMode();
}

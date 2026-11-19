import 'dart:async';

import 'package:flutter/foundation.dart';

/// The time now, for what the app shows counted from it (an age, "Updated
/// 3m ago", a pull request's last look); tests set their own, a fixed one
/// before each (`flutter_test_config.dart`), so a golden's ages never move.
DateTime Function() clock = DateTime.now;

/// The one clock what shows a running time ticks on (`LiveText`, a
/// turn's status): it tells its listeners once a second while any
/// listens, and stops as the last leaves, so no row keeps a timer of its
/// own.
final secondClock = _Seconds();

class _Seconds extends ChangeNotifier {
  Timer? _timer;

  /// Whether it ticks: something listens.
  @visibleForTesting
  bool get ticking => _timer != null;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _timer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (hasListeners) return;
    _timer?.cancel();
    _timer = null;
  }
}

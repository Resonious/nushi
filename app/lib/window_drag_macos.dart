import 'package:flutter/services.dart';

import 'package:nushi/app_log.dart';
import 'package:nushi/window_drag.dart';

const _channel = MethodChannel('nushi/window');

/// Logs each mouse release, or trackpad gesture's end, the window told
/// Flutter's engine of because the engine never had it
/// (`macos/Runner/NushiViewController.swift`, ADR 0080): what it was for
/// and which check found it, nothing more (ADR 0038). A pane's edge that
/// follows the pointer with no button held was one such.
void logMouseRepairs() => _channel.setMethodCallHandler((call) async {
  if ((call.method, call.arguments) case (
    'repaired',
    final Map<Object?, Object?> a,
  )) {
    appLog.warn('the window told the engine of a mouse release it never had', {
      'what': '${a['what']}',
      'check': '${a['check']}',
    });
  }
});

/// The Mac's window, moved and zoomed by AppKit
/// (`macos/Runner/TitleBar.swift`'s HeaderDrag) from the headers, which
/// run under its title bar.
class MacWindow implements AppWindow {
  const new();

  /// Past the traffic lights, which `macos/Runner/TitleBar.swift`'s
  /// WindowButtons puts 20 in from the window's edge and level with the
  /// headers' middle (ADR 0111): the third ends 80 in (each 14 across, 23
  /// apart), and what follows keeps the 15 it always had from it.
  @override
  double get titleInset => 95;

  @override
  bool get headersMoveWindow => true;

  @override
  bool get menuBar => true;

  /// The Swift side already brings the app forward when a notification is
  /// clicked (`macos/Runner/Alerts.swift`), and nothing else asks.
  @override
  Future<void> present({String? token}) async {}

  @override
  Future<void> arm(int micros) => _channel.invokeMethod<void>('arm', micros);

  @override
  Future<void> zoom() => _channel.invokeMethod<void>('zoom');
}

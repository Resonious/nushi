import 'dart:ffi';
import 'dart:typed_data';

import 'package:nushi/window_drag.dart';

/// Windows's window, which keeps the system's title bar (ADR 0125), as
/// Linux's does: it moves and zooms the window, so a header does neither,
/// and there's no menu bar for the app's menus. It's presented through
/// user32 by FFI (ADR 0134).
class WindowsWindow implements AppWindow {
  const new();

  /// The title bar is above the content, so nothing is in the way.
  @override
  double get titleInset => 8;

  @override
  bool get headersMoveWindow => false;

  @override
  bool get menuBar => false;

  /// Restores the window if it's minimized and brings it to the front.
  /// Windows lets a process take the foreground only while it may (the
  /// user's last input was its, or a notification's click gave it the
  /// right); otherwise the taskbar's button flashes until the window is
  /// chosen, as a desktop that only marks a window as wanting attention.
  /// Windows has no [token].
  @override
  Future<void> present({String? token}) async {
    if (!_user32.providesSymbol('SetForegroundWindow')) return;
    final window = _appWindow();
    if (window == nullptr) return;
    _showWindow(window, _isIconic(window) != 0 ? _restore : _show);
    if (_setForegroundWindow(window) != 0) return;
    final info = Uint8List(_flashInfoSize);
    ByteData.sublistView(info)
      ..setUint32(0, _flashInfoSize, Endian.little)
      ..setUint64(8, window.address, Endian.little)
      ..setUint32(16, _flashAll | _flashUntilForeground, Endian.little);
    _flashWindowEx(info.address);
  }

  @override
  Future<void> arm(int micros) async {}

  @override
  Future<void> zoom() async {}
}

/// The app's own top-level window: the first of the runner's class
/// (`windows/runner/win32_window.cpp`) that this process made, nullptr
/// without one.
Pointer<Void> _appWindow() {
  final runner = Uint16List.fromList([..._runnerClass.codeUnits, 0]);
  final pid = Uint32List(1);
  final self = _currentProcessId();
  var window = nullptr.cast<Void>();
  while (true) {
    window = _findWindowEx(nullptr, window, runner.address, nullptr);
    if (window == nullptr) return window;
    _windowProcess(window, pid.address);
    if (pid[0] == self) return window;
  }
}

/// The class Flutter's Windows runner registers for its window.
const _runnerClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

/// ShowWindow's SW_SHOW and SW_RESTORE.
const _show = 5;
const _restore = 9;

/// FLASHWINFO's size on 64-bit Windows, and its FLASHW_ALL and
/// FLASHW_TIMERNOFG: the caption and the taskbar's button, until the
/// window comes to the front.
const _flashInfoSize = 32;
const _flashAll = 0x3;
const _flashUntilForeground = 0xc;

/// user32, loaded before the first call, so the process's lookup of the
/// calls below finds it.
final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

@Native<
  Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Uint16>,
    Pointer<Uint16>,
  )
>(symbol: 'FindWindowExW', isLeaf: true)
external Pointer<Void> _findWindowEx(
  Pointer<Void> parent,
  Pointer<Void> after,
  Pointer<Uint16> className,
  Pointer<Uint16> title,
);

@Native<Uint32 Function(Pointer<Void>, Pointer<Uint32>)>(
  symbol: 'GetWindowThreadProcessId',
  isLeaf: true,
)
external int _windowProcess(Pointer<Void> window, Pointer<Uint32> pid);

@Native<Uint32 Function()>(symbol: 'GetCurrentProcessId', isLeaf: true)
external int _currentProcessId();

@Native<Int32 Function(Pointer<Void>)>(symbol: 'IsIconic', isLeaf: true)
external int _isIconic(Pointer<Void> window);

@Native<Int32 Function(Pointer<Void>, Int32)>(symbol: 'ShowWindow')
external int _showWindow(Pointer<Void> window, int command);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'SetForegroundWindow')
external int _setForegroundWindow(Pointer<Void> window);

@Native<Int32 Function(Pointer<Uint8>)>(symbol: 'FlashWindowEx', isLeaf: true)
external int _flashWindowEx(Pointer<Uint8> info);

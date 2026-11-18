import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/app_install_windows.dart';
import 'package:nushi/conventions.dart';
import 'package:nushi/desktop_windows.dart';
import 'package:nushi/native_windows.dart';

// Windows's native set, built on any machine: each capability's file
// compiles here (FFI and all), though its calls only run on Windows.

void main() {
  test("Windows's set is whole: its words, no menu bar, Explorer, and a "
      'daemon it stops by its stop event', () {
    final set = windowsNative();
    expect(set.conventions, same(windowsConventions));
    expect(set.window.menuBar, isFalse);
    expect(set.desktop, isA<WindowsDesktop>());
    expect(set.install, isA<WindowsAppInstall>());
    expect(set.install.canStop, isTrue);
  });

  test('presenting with no window of the app to find (a test has none) does '
      'nothing', () async {
    await windowsNative().window.present();
  }, skip: !Platform.isWindows);
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/files_pane.dart';
import 'package:nushi/native.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/window_drag.dart';

import 'fake_daemon.dart' show loadFonts;
import 'harness.dart';
import 'right_panes_fixture.dart';

// A side pane's top row is in the window's top band now, level with the
// chat's header (ADR 0123): on the Mac its empty space moves and zooms
// the window as a header's does (ADR 0080); on Linux, where the window
// manager's title bar does that, it does nothing to the window.

/// The platform's own window, its moves and zooms written down.
class _Window implements AppWindow {
  new(this.real);

  final AppWindow real;
  final calls = <String>[];

  @override
  double get titleInset => real.titleInset;

  @override
  bool get headersMoveWindow => real.headersMoveWindow;

  @override
  bool get menuBar => real.menuBar;

  @override
  Future<void> present({String? token}) async => calls.add('present');

  @override
  Future<void> arm(int micros) async => calls.add('arm');

  @override
  Future<void> zoom() async => calls.add('zoom');
}

void main() {
  setUpAll(loadFonts);

  testWidgets("a beside pane's top row zooms and moves the window on the "
      'Mac, and does nothing to it on Linux', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: 1700,
      open: (
        side: false,
        files: true,
        subagent: false,
        command: false,
        previews: 0,
        browser: 0,
      ),
    );
    final real = native.window;
    final window = _Window(real);
    native.window = window;
    addTearDown(() => native.window = real);
    final row = tester.getRect(
      find
          .descendant(
            of: find.byType(FilesPane),
            matching: find.byType(PaneHeader),
          )
          .first,
    );
    // Beside the chat: the row is in the window's top band.
    expect(row.top, NushiTheme.windowPad);
    // Its empty space, between the title and the buttons.
    final empty = Offset(row.left + row.width * 0.55, row.center.dy);
    await tester.tapAt(empty);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(empty);
    await tester.pumpAndSettle();
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    expect(window.calls.where((c) => c == 'zoom'), hasLength(mac ? 1 : 0));
    expect(window.calls.contains('arm'), mac);
    await closeView(tester, d);
  }, variant: macAndLinux);
}

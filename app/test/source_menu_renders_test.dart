import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/main.dart';
import 'package:nushi/source_view.dart';
import 'package:re_editor/re_editor.dart';

import 'fake_daemon.dart' show loadFonts;
import 'file_edit_helpers.dart';
import 'harness.dart';

// The right-click menu in a file's source in the Files pane (issue 75),
// looked at full size: over the editor with lines selected, and over a
// read-only source, at both widths in both themes.

/// Lines ending both in CRLF and LF: shown read-only.
final List<int> _mixed = utf8.encode('package main\r\n\nfunc main() {\n}\n');

void main() {
  setUpAll(loadFonts);

  for (final brightness in Brightness.values) {
    final theme = brightness.name;
    for (final width in [1700.0, 720.0]) {
      final w = width.toInt();
      testWidgets(
        'renders: the menu in the editor and the source, $w, $theme',
        (tester) async {
          final (d, _) = await openEditor(
            tester,
            {'main.go': utf8.encode(tabbed), 'mixed.go': _mixed},
            width: width,
            brightness: brightness,
          );
          final app = find.byType(NushiApp);
          editOf(d).controller.selection = const CodeLineSelection(
            baseIndex: 5,
            baseOffset: 0,
            extentIndex: 7,
            extentOffset: 6,
          );
          await tester.pumpAndSettle();
          final editor = tester.getRect(find.byType(CodeEditor));
          await tester.tapAt(
            Offset(editor.left + 160, editor.top + 140),
            buttons: kSecondaryButton,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          await render(tester, app, 'menu75_${w}_editor_$theme');
          await tester.tapAt(editor.bottomLeft + const Offset(40, -20));
          await tester.pumpAndSettle();

          chatC(d).openInFiles('mixed.go');
          await tester.pumpAndSettle();
          final view = tester.getRect(find.byType(SourceView));
          // Nothing selected here: the first full repaint after a drag in a
          // read-only source trips Flutter's selection painting
          // (MultiSelectableSelectionContainerDelegate._calculateLocalRange),
          // with or without this menu.
          await tester.tapAt(
            Offset(view.left + 120, view.top + 50),
            buttons: kSecondaryButton,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          await render(tester, app, 'menu75_${w}_source_$theme');
          await endEditor(tester, d);
        },
        variant: onMac,
      );
    }
  }
}

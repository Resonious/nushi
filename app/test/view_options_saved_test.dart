import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/settings.dart';

import 'harness.dart';
import 'right_panes_fixture.dart';
import 'view_options_fixture.dart';

// The Files pane's view options as another run saved them, none at its
// default (ADR 0123): the ⋯, the View menu and the palette show each as
// saved from the start.

const PanesOpen _files = (
  side: false,
  files: true,
  subagent: false,
  command: false,
  previews: 0,
  browser: 0,
);

void main() {
  setUpAll(() {
    // Written before anything reads it: as the app finds it at launch.
    File('$dataDir/app.json').writeAsStringSync(
      jsonEncode({
        'previewTabs': false,
        'wrap': false,
        'indentGuides': false,
        'whitespace': true,
        'scrollPastEnd': true,
        'tabSize': 8,
        'filesTreeSide': 'left',
      }),
    );
  });

  testWidgets('each place shows each option as saved', (tester) async {
    final (d, _) = await panesApp(tester, width: 1700, open: _files);
    final view = [for (final m in viewItems(tester)) m.label];
    final saved = readSaved();
    await openFilesMore(tester);
    for (final o in toggleWords) {
      final on = saved[o.key]! as bool;
      expect(o.pref.value, on, reason: o.key);
      expect(view, contains(on ? o.viewOn : o.viewOff));
      expect(
        paletteRow(tester, d, o.act).title,
        on ? o.paletteOn : o.paletteOff,
      );
      expect(menuChecked(o.row), on, reason: o.row);
    }
    await closeMenus(tester);
    for (final c in choiceWords) {
      final (value, name, _, act, _) = c.values.firstWhere(
        (v) => v.$3 == saved[c.key],
      );
      expect(c.pref.value, value, reason: c.key);
      expect(
        viewSubmenu(
          tester,
          c.view,
        ).menus.firstWhere((m) => m.label == name).onSelected,
        isNull,
      );
      expect(paletteRow(tester, d, act).enabled, isFalse);
      await openFilesMore(tester);
      expect(
        find.descendant(of: menuRow(c.row), matching: find.text(name)),
        findsOneWidget,
      );
      await closeMenus(tester);
    }
    await closeView(tester, d);
  }, variant: onMac);
}

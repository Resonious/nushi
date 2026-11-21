import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/settings.dart';

import 'fake_daemon.dart' show loadFonts;
import 'harness.dart';
import 'right_panes_fixture.dart';
import 'view_options_fixture.dart';

// The Files pane's view options (ADR 0123): each is one pref, and the ⋯,
// the View menu and the palette all flip it and all show it, and it's
// saved.

const PanesOpen _files = (
  side: false,
  files: true,
  subagent: false,
  command: false,
  previews: 0,
  browser: 0,
);

void main() {
  setUpAll(loadFonts);

  for (final o in toggleWords) {
    testWidgets('${o.row}: the ⋯, View and the palette flip it and all say '
        'so, and it’s saved', (tester) async {
      final (d, _) = await panesApp(tester, width: 1700, open: _files);
      Future<void> expectEverywhere({required bool on}) async {
        expect(o.pref.value, on);
        expect(readSaved()[o.key], on);
        expect([
          for (final m in viewItems(tester)) m.label,
        ], contains(on ? o.viewOn : o.viewOff));
        expect(
          paletteRow(tester, d, o.act).title,
          on ? o.paletteOn : o.paletteOff,
        );
        await openFilesMore(tester);
        expect(menuChecked(o.row), on);
        await closeMenus(tester);
      }

      final start = o.pref.value;
      await expectEverywhere(on: start);
      // The ⋯.
      await openFilesMore(tester);
      await tester.tap(find.text(o.row));
      await tester.pumpAndSettle();
      await expectEverywhere(on: !start);
      // View.
      viewItems(tester)
          .firstWhere((m) => m.label == (start ? o.viewOff : o.viewOn))
          .onSelected!();
      await tester.pumpAndSettle();
      await expectEverywhere(on: start);
      // The palette.
      paletteRow(tester, d, o.act).run();
      await tester.pumpAndSettle();
      await expectEverywhere(on: !start);
      await closeView(tester, d);
    }, variant: onMac);
  }

  for (final c in choiceWords) {
    testWidgets('${c.row}: the ⋯, View and the palette set it and all show '
        'it, and it’s saved', (tester) async {
      final (d, _) = await panesApp(tester, width: 1700, open: _files);
      Future<void> expectEverywhere(int at) async {
        final (value, name, saved, _, _) = c.values[at];
        expect(c.pref.value, value);
        expect(readSaved()[c.key], saved);
        // View: the value now disabled, the rest not.
        final view = viewSubmenu(tester, c.view).menus;
        expect(
          [for (final m in view) m.label],
          [for (final v in c.values) v.$2],
        );
        for (final m in view) {
          expect(m.onSelected == null, m.label == name, reason: m.label);
        }
        // The palette: a row for each value but the one now.
        for (final (v, _, _, act, palette) in c.values) {
          final row = paletteRow(tester, d, act);
          expect(row.title, palette);
          expect(row.enabled, v != value, reason: palette);
        }
        // The ⋯: its row says the value now, its submenu checks it.
        await openFilesMore(tester);
        expect(
          find.descendant(of: menuRow(c.row), matching: find.text(name)),
          findsOneWidget,
        );
        await tester.tap(find.text(c.row));
        await tester.pumpAndSettle();
        for (final v in c.values) {
          expect(menuChecked(v.$2), v.$2 == name, reason: v.$2);
        }
        await closeMenus(tester);
      }

      final start = c.values.indexWhere((v) => v.$1 == c.pref.value);
      await expectEverywhere(start);
      final others = [
        for (var i = 0; i < c.values.length; i++)
          if (i != start) i,
      ];
      // The ⋯.
      await openFilesMore(tester);
      await tester.tap(find.text(c.row));
      await tester.pumpAndSettle();
      await tester.tap(find.text(c.values[others.first].$2).last);
      await tester.pumpAndSettle();
      await expectEverywhere(others.first);
      // View.
      viewSubmenu(tester, c.view).menus
          .firstWhere((m) => m.label == c.values[others.last].$2)
          .onSelected!();
      await tester.pumpAndSettle();
      await expectEverywhere(others.last);
      // The palette.
      paletteRow(tester, d, c.values[start].$4).run();
      await tester.pumpAndSettle();
      await expectEverywhere(start);
      await closeView(tester, d);
    }, variant: onMac);
  }
}

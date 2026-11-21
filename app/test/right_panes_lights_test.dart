import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/beside_fit.dart';
import 'package:nushi/browser_pane.dart';
import 'package:nushi/chat_panes.dart';
import 'package:nushi/files_pane.dart';
import 'package:nushi/main.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/side_chat.dart';
import 'package:nushi/sidebar_button.dart';
import 'package:nushi/subagent_pane.dart';

import 'browser_fixture.dart' show browserFakes;
import 'fake_daemon.dart' show loadFonts;
import 'harness.dart';
import 'right_panes_fixture.dart';

// With the sidebar hidden, the panes run up into the window's top row,
// where the title buttons (the sidebar's, Back, Forward; ADR 0118) sit at
// its left. However narrow the window, nothing in the first pane's top row
// lies under them, and nothing in any pane's runs past its edge (ADR 0123).

PanesOpen _open({
  bool side = false,
  bool files = false,
  bool subagent = false,
  int previews = 0,
  int browser = 0,
}) => (
  side: side,
  files: files,
  subagent: subagent,
  command: false,
  previews: previews,
  browser: browser,
);

/// Each pane that can be first, with the panes that open after it in the
/// widest set it's first of.
final _firsts = <(String, Type, PanesOpen, List<PaneSpec>)>[
  (
    'side chat',
    SideChat,
    _open(side: true, files: true, previews: 1, browser: 1),
    [ChatPanes.side, ChatPanes.files, ChatPanes.browser],
  ),
  (
    'Files',
    FilesPane,
    _open(files: true, previews: 1, browser: 1),
    [ChatPanes.files, ChatPanes.browser],
  ),
  ('subagent', SubagentPane, _open(subagent: true), [ChatPanes.subagent]),
  ('Files alone', FilesPane, _open(previews: 1), [ChatPanes.files]),
  ('browser', BrowserPane, _open(browser: 1), [ChatPanes.browser]),
];

void main() {
  setUpAll(loadFonts);

  for (final (name, type, open, specs) in _firsts) {
    testWidgets('$name first, the sidebar hidden: from its lie-over line '
        'down to 720 a point at a time, nothing in its top row under the '
        'title buttons, and nothing overflows', (tester) async {
      browserFakes();
      final line = windowFor(besideFrom(specs)!, sidebar: false);
      final from = line + 3;
      final to = line - 3 < 720 ? line - 3 : 720.0;
      var (d, _) = await panesApp(tester, width: from, open: open);
      void check(double w) {
        expect(tester.takeException(), isNull, reason: 'overflow at $w');
        final buttons = tester.getRect(find.byType(TitleButtons));
        final row = find
            .descendant(
              of: find.byType(type),
              matching: find.byType(PaneHeader),
            )
            .first;
        final parts = find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (w) => w is RichText || w is Icon || w is Tooltip,
          ),
        );
        expect(parts, findsWidgets);
        for (final e in parts.evaluate()) {
          final box = e.renderObject! as RenderBox;
          final r = box.localToGlobal(Offset.zero) & box.size;
          if (r.isEmpty) continue;
          expect(
            r.overlaps(buttons),
            isFalse,
            reason: '${e.widget.runtimeType} at $r, under $buttons at $w',
          );
        }
        // The pane's row inside the pane.
        final pane = tester.getRect(find.byType(type));
        expect(tester.getRect(row).left, greaterThanOrEqualTo(pane.left));
        expect(tester.getRect(row).right, lessThanOrEqualTo(pane.right));
      }

      await narrowing(
        tester,
        from: from,
        to: to,
        check: check,
        reopen: () async {
          await closeView(tester, d);
          (d, _) = await panesApp(tester, width: from, open: open);
        },
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await render(
        tester,
        find.byType(NushiApp),
        'lights_${name.replaceAll(' ', '_')}_${to.toInt()}',
      );
      await closeView(tester, d);
    }, variant: onMac);
  }
}

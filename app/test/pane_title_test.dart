import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/files_pane.dart';
import 'package:nushi/main.dart';
import 'package:nushi/pane_title.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/side_chat.dart';

import 'fake_daemon.dart' show loadFonts;
import 'harness.dart';
import 'right_panes_fixture.dart';

// A pane narrowed for a narrow window shortens the words in its top row,
// never its buttons, and never runs past its edge (ADR 0123).

void main() {
  setUpAll(loadFonts);

  /// What shows of a [PaneTitle] [width] wide.
  Future<List<String>> shows(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      themed(
        Center(
          child: SizedBox(
            width: width,
            child: const PaneTitle(
              title: Text('Side chat'),
              caption: Text('not added to the chat'),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull, reason: 'at $width');
    return [
      for (final e in find.byType(Text).evaluate())
        if (tester.getSize(find.byWidget(e.widget)).width > 0)
          (e.widget as Text).data!,
    ];
  }

  testWidgets('the caption is cut, then goes, then the title is cut, then '
      'goes', (tester) async {
    expect(await shows(tester, 400), ['Side chat', 'not added to the chat']);
    // Room for the title and a few letters of the caption.
    final title = tester.getSize(find.text('Side chat')).width;
    expect(await shows(tester, title + 8 + PaneTitle.captionLeast), [
      'Side chat',
      'not added to the chat',
    ]);
    final cut = tester.renderObject<RenderParagraph>(
      find.text('not added to the chat'),
    );
    expect(cut.didExceedMaxLines, isTrue);
    expect(await shows(tester, title + 8 + PaneTitle.captionLeast - 1), [
      'Side chat',
    ]);
    expect(await shows(tester, title), ['Side chat']);
    expect(await shows(tester, PaneTitle.titleLeast), ['Side chat']);
    expect(
      tester.renderObject<RenderParagraph>(find.text('Side chat')).size.width,
      lessThanOrEqualTo(PaneTitle.titleLeast),
    );
    expect(await shows(tester, PaneTitle.titleLeast - 1), isEmpty);
    expect(await shows(tester, 0), isEmpty);
  });

  testWidgets('the side chat and Files narrowed alike in a narrow window, '
      'checked as a point at a time would: their rows keep every button '
      'inside the pane, and nothing overflows', (tester) async {
    // The side chat, Files and the preview need 800; a window of 720 with
    // the sidebar shown leaves the chat 452.
    const open = (
      side: true,
      files: true,
      subagent: false,
      command: false,
      previews: 1,
      browser: 0,
    );
    var (d, _) = await panesApp(tester, width: 1080, sidebar: true, open: open);
    void check(double w) {
      expect(tester.takeException(), isNull, reason: 'at $w');
      for (final (pane, tips) in [
        (SideChat, ['Keep as chat', 'End the side chat']),
        (FilesPane, ['Close']),
      ]) {
        final rect = tester.getRect(find.byType(pane));
        final row = tester.getRect(
          find
              .descendant(
                of: find.byType(pane),
                matching: find.byType(PaneHeader),
              )
              .first,
        );
        for (final tip in tips) {
          final button = find.descendant(
            of: find.byType(pane),
            matching: find.byWidgetPredicate(
              (w) => w is Tooltip && (w.message ?? '').startsWith(tip),
            ),
          );
          final r = tester.getRect(button.first);
          expect(row.contains(r.center), isTrue, reason: '$tip at $w');
          expect(r.right, lessThanOrEqualTo(rect.right), reason: '$tip at $w');
        }
      }
    }

    await narrowing(
      tester,
      from: 1080,
      to: 720,
      check: check,
      reopen: () async {
        await closeView(tester, d);
        (d, _) = await panesApp(tester, width: 1080, sidebar: true, open: open);
      },
    );
    await tester.pumpAndSettle();
    await render(tester, find.byType(NushiApp), 'pane_title_720_sidebar');
    await closeView(tester, d);
  }, variant: onMac);
}

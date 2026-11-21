import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/browser_pane.dart';
import 'package:nushi/chat_header.dart';
import 'package:nushi/chat_view.dart';
import 'package:nushi/files_pane.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/side_chat.dart';
import 'package:nushi/terminal_panel.dart';
import 'package:nushi/transcript.dart';

import 'browser_fixture.dart' show browserFakes;
import 'fake_daemon.dart' show loadFonts;
import 'harness.dart';
import 'right_panes_fixture.dart';

// The panes lying over the transcript (ADR 0123): narrower than they need
// at their least, they still run the pane's full height with their own top
// rows, and the chat (its header, transcript and terminal) keeps its least
// width under them, covered at its right. The layout is the same either
// side of that line.

const PanesOpen _three = (
  side: true,
  files: true,
  subagent: false,
  command: false,
  previews: 1,
  browser: 1,
);

const PanesOpen _filesBrowser = (
  side: false,
  files: true,
  subagent: false,
  command: false,
  previews: 1,
  browser: 1,
);

final Finder _transcript = find.byWidgetPredicate(
  (w) => w is Transcript && w.items == null && w.chat.id == 'c',
);

/// The pane's own top row: its first [PaneHeader].
Finder _topRow(Type pane) => find
    .descendant(of: find.byType(pane), matching: find.byType(PaneHeader))
    .first;

/// Whether [pane]'s backing casts the shadow that falls on the transcript.
bool _shadowed(WidgetTester tester, Type pane) => tester
    .widgetList<DecoratedBox>(
      find.ancestor(of: find.byType(pane), matching: find.byType(DecoratedBox)),
    )
    .any(
      (b) => switch (b.decoration) {
        BoxDecoration(:final boxShadow?) => boxShadow.isNotEmpty,
        _ => false,
      },
    );

void main() {
  setUpAll(loadFonts);

  testWidgets('over the transcript: the panes from the top with their own '
      "rows, the chat's header, transcript and terminal at its least under "
      "them, the first one's shadow on it", (tester) async {
    // 1400 for the chat: under the 1460 the three need at their least,
    // and with the sidebar hidden room for all three past the title
    // buttons (1100 of 1211), so none is squeezed.
    browserFakes();
    final (d, _) = await panesApp(
      tester,
      width: windowFor(1400, sidebar: false),
      terminal: true,
      open: _three,
    );
    final area = tester.getRect(find.byType(Pane));
    final header = tester.getRect(find.byType(ChatHeader));
    const least = ChatView.leastBesideWide;
    // The header, at the pane's top and its least wide; never across the
    // panes.
    expect(header.top, area.top);
    expect(header.left, area.left);
    expect(header.width, least);
    expect(
      tester.getRect(find.byTooltip('Chat menu')).right,
      header.right - ChatHeader.end,
    );
    // The transcript and the terminal as wide, under it.
    final transcript = tester.getRect(_transcript);
    expect(transcript.left, area.left);
    expect(transcript.width, least);
    final terminal = tester.getRect(find.byType(TerminalPanel));
    expect(terminal.left, area.left);
    expect(terminal.width, least);
    // The panes, each at its least, left to right to the pane's right
    // edge, from its top to its bottom, each top row level with the
    // header.
    final types = [SideChat, FilesPane, BrowserPane];
    final panes = [for (final t in types) tester.getRect(find.byType(t))];
    for (final (i, w) in [300.0, 500.0, 300.0].indexed) {
      expect(panes[i].width, w);
      expect(panes[i].top, area.top);
      expect(panes[i].bottom, area.bottom);
      if (i > 0) expect(panes[i].left, panes[i - 1].right);
      final row = tester.getRect(_topRow(types[i]));
      expect(row.top, header.top);
      expect(row.bottom, header.bottom);
    }
    expect(panes.last.right, area.right);
    // They cover the chat's right.
    expect(panes.first.left, area.left + 1400 - 1100);
    expect(panes.first.left, lessThan(header.right));
    expect(_shadowed(tester, SideChat), isTrue);
    expect(_shadowed(tester, FilesPane), isFalse);
    expect(_shadowed(tester, BrowserPane), isFalse);
    expect(tester.takeException(), isNull);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('stepped a point at a time across the line, the panes and '
      'the header move a point at most, and the header never spans them', (
    tester,
  ) async {
    // Files and the browser need 1160 of the chat at their least: the
    // line is at a window of 1428 with the sidebar.
    final line = windowFor(1160, sidebar: true);
    browserFakes();
    final (d, _) = await panesApp(
      tester,
      width: line + 4,
      sidebar: true,
      terminal: true,
      open: _filesBrowser,
    );
    Rect? files;
    Rect? header;
    for (var w = line + 4; w >= line - 4; w--) {
      viewport(tester, Size(w, 900));
      await tester.pumpAndSettle();
      final area = tester.getRect(find.byType(Pane));
      final f = tester.getRect(find.byType(FilesPane));
      final h = tester.getRect(find.byType(ChatHeader));
      expect(f.top, area.top, reason: 'at $w');
      expect(f.bottom, area.bottom, reason: 'at $w');
      expect(h.top, area.top, reason: 'at $w');
      expect(
        h.right,
        lessThanOrEqualTo(tester.getRect(find.byType(BrowserPane)).left),
      );
      if (files != null) {
        expect((f.left - files.left).abs(), lessThanOrEqualTo(1), reason: '$w');
        expect((h.width - header!.width).abs(), lessThanOrEqualTo(1));
      }
      files = f;
      header = h;
    }
    // From the line down, the header keeps the transcript's least.
    expect(header!.width, ChatView.leastBesideWide);
    expect(files!.left, lessThan(header.right));
    expect(tester.takeException(), isNull);
    await closeView(tester, d);
  }, variant: onMac);
}

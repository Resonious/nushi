import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/chat_header.dart';
import 'package:nushi/chat_view.dart';
import 'package:nushi/details_panel.dart';
import 'package:nushi/file_view.dart';
import 'package:nushi/files_pane.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/subagent_pane.dart';
import 'package:nushi/terminal_panel.dart';
import 'package:nushi/transcript.dart';

import 'fake_daemon.dart' show loadFonts;
import 'harness.dart';
import 'right_panes_fixture.dart';

// The chat area lays its header, its view, its panes, its details and its
// terminal out in one Beside (ADR 0123): what changes beside the
// transcript builds it no more, and the header and the terminal outlive
// a change of tab.

/// The chat's own transcript, not a side chat's or a subagent's.
bool _chatTranscript(Widget w) =>
    w is Transcript && w.items == null && w.chat.id == 'c';

void main() {
  setUpAll(loadFonts);

  testWidgets('opening, dragging and closing panes rebuild neither the '
      'chat view nor its transcript', (tester) async {
    final (d, _) = await panesApp(tester, width: 1900);
    var views = 0;
    debugOnRebuildDirtyWidget = (e, _) {
      if (e.widget is ChatView) views++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    // The transcript's widget is the one first built: nothing above it
    // built it again (it may lay itself out anew at a new width).
    final transcript = find.byWidgetPredicate(_chatTranscript);
    final first = tester.widget(transcript);
    await openPanesIn(tester, d, (
      side: true,
      files: true,
      subagent: false,
      command: false,
      previews: 0,
      browser: 0,
    ));
    d.chats['c']!.pane.value = 'a';
    await tester.pumpAndSettle();
    // The Files pane's edge, dragged 40 points wider and let go.
    final files = tester.getRect(find.byType(FilesPane));
    final drag = await tester.startGesture(
      Offset(files.left + Resizable.edgeWidth / 2, files.center.dy),
    );
    for (var i = 0; i < 8; i++) {
      await drag.moveBy(const Offset(-5, 0));
      await tester.pump();
      expect(tester.widget(transcript), same(first));
    }
    await drag.up();
    await tester.pump(const Duration(seconds: 2)); // the width's saved
    d.chats['c']!.pane.value = null;
    filesChats.value = {};
    await tester.pumpAndSettle();
    expect(views, 0);
    expect(tester.widget(transcript), same(first));
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('the rail tucking and coming back, by a pane opening and by '
      'its edge dragged, rebuilds neither the chat view nor its '
      'transcript', (tester) async {
    // A chat area of 1100: the Files pane needs the rail's room (1500).
    final (d, _) = await panesApp(
      tester,
      width: windowFor(1100, sidebar: false),
    );
    var views = 0;
    debugOnRebuildDirtyWidget = (e, _) {
      if (e.widget is ChatView) views++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    final transcript = find.byWidgetPredicate(_chatTranscript);
    final first = tester.widget(transcript);
    bool tucked() =>
        find.byType(DetailsPanel).evaluate().isEmpty &&
        find.byType(DetailsPanel, skipOffstage: false).evaluate().isNotEmpty;
    expect(tucked(), isFalse);
    final c = d.chats['c']!..openInFiles('PLAN.md');
    await tester.pumpAndSettle();
    expect(tucked(), isTrue);
    expect(tester.widget(transcript), same(first));
    toggleFiles(c);
    await tester.pumpAndSettle();
    expect(tucked(), isFalse);
    // A subagent's pane (264) leaves the rail its room, until its edge is
    // dragged past 420 (the transcript would keep under 360), and back.
    c.pane.value = 'a';
    await tester.pumpAndSettle();
    expect(tucked(), isFalse);
    final pane = tester.getRect(find.byType(SubagentPane));
    final drag = await tester.startGesture(
      Offset(pane.left + Resizable.edgeWidth / 2, pane.center.dy),
    );
    await drag.moveBy(const Offset(-20, 0));
    await tester.pump();
    var flips = 0;
    var was = tucked();
    for (final by in [
      for (var i = 0; i < 40; i++) -5.0,
      for (var i = 0; i < 40; i++) 5.0,
    ]) {
      await drag.moveBy(Offset(by, 0));
      await tester.pumpAndSettle();
      if (tucked() != was) flips++;
      was = tucked();
      expect(tester.widget(transcript), same(first));
    }
    expect(flips, 2);
    await drag.up();
    await tester.pump(const Duration(seconds: 2)); // the width's saved
    c.pane.value = null;
    await tester.pumpAndSettle();
    expect(views, 0);
    expect(tester.widget(transcript), same(first));
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('the terminal and the header stay the same widgets from tab '
      'to tab, with a pane open, and nothing slides', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: 1900,
      terminal: true,
      open: (
        side: false,
        files: false,
        subagent: false,
        command: false,
        previews: 1,
        browser: 0,
      ),
    );
    final c = d.chats['c']!;
    final panel = tester.state(find.byType(TerminalPanel));
    final terminal = tester.getRect(find.byType(TerminalPanel));
    final preview = tester.getRect(find.byType(FileView));
    final header = tester.element(find.byType(ChatHeader));
    expect(find.byType(DetailsPanel), findsOneWidget);

    c.tab.value = ChatTab.changes;
    await tester.pump();
    expect(tester.state(find.byType(TerminalPanel)), same(panel));
    expect(tester.element(find.byType(ChatHeader)), same(header));
    // On Changes: no pane, no details, the header across the pane.
    expect(find.byType(FileView), findsNothing);
    expect(find.byType(DetailsPanel), findsNothing);
    final pane = tester.getRect(find.byType(Pane));
    expect(tester.getRect(find.byType(ChatHeader)).width, pane.width);
    // The terminal didn't slide in again.
    expect(tester.getRect(find.byType(TerminalPanel)).height, terminal.height);
    await tester.pumpAndSettle();

    c.tab.value = ChatTab.chat;
    await tester.pump();
    expect(tester.state(find.byType(TerminalPanel)), same(panel));
    expect(tester.element(find.byType(ChatHeader)), same(header));
    // The preview is where it was on the first frame: no slide.
    expect(tester.getRect(find.byType(FileView)), preview);
    expect(tester.getRect(find.byType(TerminalPanel)), terminal);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(FileView)), preview);
    await closeView(tester, d);
  }, variant: onMac);
}

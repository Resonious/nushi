import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/chat_header.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/details_panel.dart';
import 'package:nushi/file_view.dart';
import 'package:nushi/files_pane.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/subagent_pane.dart';
import 'package:nushi/transcript.dart';

import 'fake_daemon.dart' show loadFonts;
import 'harness.dart';
import 'right_panes_fixture.dart';

// How the rail and the header's buttons move as panes come and go (ADR
// 0123): the rail slides out under an opening pane and back as it goes,
// turning back from where it is; the header's buttons glide with the pane
// in step; a tab's change or Reduce Motion puts all of it in place at once.

PanesOpen _open({
  bool side = false,
  bool files = false,
  bool subagent = false,
  int previews = 0,
}) => (
  side: side,
  files: files,
  subagent: subagent,
  command: false,
  previews: previews,
  browser: 0,
);

final Finder _rail = find.byType(DetailsPanel);
final Finder _menu = find.byTooltip('Chat menu');

void main() {
  setUpAll(loadFonts);

  // The chat's pane 1100 wide, the sidebar hidden: the rail shows alone,
  // and tucks for the preview (1240), which stays beside (920).
  final width = windowFor(1100, sidebar: false);

  testWidgets('a pane that needs its room: the rail slides out under it, '
      'taking no pointer or focus, and back as it closes', (tester) async {
    final (d, _) = await panesApp(tester, width: width);
    final c = d.chats['c']!;
    final at = tester.getRect(_rail);
    c.openInFiles('PLAN.md');
    await tester.pump();
    expect(tester.getRect(_rail).left, closeTo(at.left, 0.5));
    await tester.pump(Motion.exit ~/ 2);
    final mid = tester.getRect(_rail).left;
    expect(mid, greaterThan(at.left + 20));
    final going = find.ancestor(
      of: _rail,
      matching: find.byType(IgnorePointer),
    );
    expect(
      tester.widgetList<IgnorePointer>(going).any((w) => w.ignoring),
      isTrue,
    );
    expect(
      tester
          .widgetList<ExcludeFocus>(
            find.ancestor(of: _rail, matching: find.byType(ExcludeFocus)),
          )
          .any((w) => w.excluding),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(_rail, findsNothing);
    expect(find.byType(DetailsPanel, skipOffstage: false), findsOneWidget);

    // Closed: it slides back in from the right, to where it was.
    toggleFiles(c);
    await tester.pump();
    final first = tester.getRect(_rail).left;
    expect(first, greaterThan(at.left + 100));
    await tester.pump(Motion.enter ~/ 2);
    final half = tester.getRect(_rail).left;
    expect(half, lessThan(first));
    expect(half, greaterThan(at.left));
    await tester.pumpAndSettle();
    expect(tester.getRect(_rail), at);
    await closeView(tester, d);
  }, variant: onMac);

  for (final way in ['another chat', 'another tab']) {
    testWidgets('first seen tucked ($way and back), it slides in from the '
        'right as the pane closes', (tester) async {
      final (d, _) = await panesApp(tester, width: width);
      final c = d.chats['c']!;
      final at = tester.getRect(_rail);
      c.openInFiles('PLAN.md');
      await tester.pumpAndSettle();
      // The chat's area made again with the rail tucked from the start.
      if (way == 'another chat') {
        d.select('d');
        await tester.pumpAndSettle();
        d.select('c');
      } else {
        c.tab.value = ChatTab.changes;
        await tester.pumpAndSettle();
        c.tab.value = ChatTab.chat;
      }
      await tester.pumpAndSettle();
      expect(_rail, findsNothing);
      toggleFiles(c);
      await tester.pump();
      // From past its place on the right, never from the left of it.
      expect(tester.getRect(_rail).left, greaterThan(at.left + 200));
      var last = tester.getRect(_rail).left;
      for (var i = 0; i < 6; i++) {
        await tester.pump(Motion.enter ~/ 8);
        final now = tester.getRect(_rail).left;
        expect(now, lessThanOrEqualTo(last));
        expect(now, greaterThanOrEqualTo(at.left));
        last = now;
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(_rail), at);
      await closeView(tester, d);
    }, variant: onMac);
  }

  testWidgets('turned back mid-way, it goes from where it is, the same '
      'panel', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: width,
      open: _open(previews: 1),
    );
    final c = d.chats['c']!;
    final panel = tester.state(find.byType(DetailsPanel, skipOffstage: false));
    final shown = c.shownFile!;
    toggleFiles(c);
    await tester.pump();
    await tester.pump(Motion.enter ~/ 3);
    final mid = tester.getRect(_rail).left;
    c.openInFiles(shown);
    await tester.pump();
    expect(tester.getRect(_rail).left, closeTo(mid, 2));
    await tester.pumpAndSettle();
    expect(_rail, findsNothing);
    expect(
      tester.state(find.byType(DetailsPanel, skipOffstage: false)),
      same(panel),
    );
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('the transcript is laid out at its new width at once, its '
      'text gliding there', (tester) async {
    // Wide: the text's column keeps its width, so it glides.
    final (d, _) = await panesApp(
      tester,
      width: windowFor(2444, sidebar: false),
      open: _open(files: true),
    );
    final question = find.text('Where is the login redirect handled?');
    final view = find.byWidgetPredicate(
      (w) => w is Transcript && w.items == null && w.chat.id == 'c',
    );
    final from = tester.getRect(question).left;
    final width = tester.getSize(view).width;
    filesChats.value = {};
    await tester.pump();
    // Laid out at once 820 wider; the text drawn where it was.
    expect(tester.getSize(view).width, width + 820);
    expect(tester.getRect(question).left, closeTo(from, 1));
    await tester.pump(Motion.enter ~/ 2);
    final mid = tester.getRect(question).left;
    await tester.pumpAndSettle();
    final to = tester.getRect(question).left;
    expect(to, greaterThan(from + 100));
    expect(mid, inExclusiveRange(from, to));
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets("the header's buttons glide with an opening pane, in step, "
      'and come out from under one closing', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: windowFor(2000, sidebar: false),
    );
    final area = tester.getRect(find.byType(Pane));
    filesChats.value = {'c'};
    await tester.pump();
    for (final at in [
      Motion.enter ~/ 4,
      Motion.enter ~/ 4,
      Motion.enter ~/ 4,
    ]) {
      await tester.pump(at);
      final pane = tester.getRect(find.byType(FilesPane));
      expect(
        tester.getRect(_menu).right,
        closeTo(pane.left - ChatHeader.end, 1),
      );
    }
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_menu).right,
      tester.getRect(find.byType(FilesPane)).left - ChatHeader.end,
    );
    final start = tester.getRect(_menu).right;
    filesChats.value = {};
    await tester.pump();
    await tester.pump(Motion.exit ~/ 2);
    // The buttons come out from under the leaving pane, drawn over them.
    final mid = tester.getRect(_menu).right;
    expect(mid, inExclusiveRange(start, area.right - ChatHeader.end));
    await tester.pumpAndSettle();
    expect(tester.getRect(_menu).right, area.right - ChatHeader.end);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('opening a pane moves the buttons by its width, with the '
      'rail shown and with it tucked', (tester) async {
    for (final (area, open, pane) in [
      // The rail shown before and after: Files.
      (2000.0, _open(), 820.0),
      // Tucked before and after: a subagent's pane (944 for the rail)
      // beside a side chat; Files is wider than a tucked rail ever leaves
      // room for (ADR 0123), so the subagent's pane opens here.
      (1100.0, _open(side: true), 264.0),
    ]) {
      final (d, _) = await panesApp(
        tester,
        width: windowFor(area, sidebar: false),
        open: open,
      );
      final before = tester.getRect(_menu).right;
      if (pane == 820) {
        filesChats.value = {'c'};
      } else {
        d.chats['c']!.pane.value = 'a';
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(_menu).right, before - pane);
      await closeView(tester, d);
    }
  }, variant: onMac);

  testWidgets('the details shown or hidden with a pane open move nothing in '
      'the header', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: windowFor(1600, sidebar: false),
      open: _open(subagent: true),
    );
    Map<String, Rect> marks() => {
      'header': tester.getRect(find.byType(ChatHeader)),
      'menu': tester.getRect(_menu),
      'pane': tester.getRect(find.byType(SubagentPane)),
      for (final tip in ['Hide details', 'Show details'])
        if (find.byTooltip(tip).evaluate().isNotEmpty)
          'details': tester.getRect(find.byTooltip(tip)),
    };
    final before = marks();
    showDetails.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(marks(), before);
    await tester.pumpAndSettle();
    expect(marks(), before);
    showDetails.value = true;
    await tester.pump(const Duration(milliseconds: 60));
    expect(marks(), before);
    await tester.pumpAndSettle();
    expect(marks(), before);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('another tab and back, a preview open: nothing slides, the '
      'buttons where they go on the first frame', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: width,
      open: _open(previews: 1),
    );
    final c = d.chats['c']!;
    final menu = tester.getRect(_menu);
    final area = tester.getRect(find.byType(Pane));
    c.tab.value = ChatTab.changes;
    await tester.pump();
    expect(tester.getRect(_menu).right, area.right - ChatHeader.end);
    await tester.pumpAndSettle();
    c.tab.value = ChatTab.chat;
    await tester.pump();
    expect(tester.getRect(_menu), menu);
    expect(
      tester.getRect(find.byType(FileView)).left,
      menu.right + ChatHeader.end,
    );
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('under Reduce Motion the rail, the pane and the buttons are '
      'where they go at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final (d, _) = await panesApp(tester, width: width);
    final c = d.chats['c']!..openInFiles('PLAN.md');
    await tester.pump();
    final preview = tester.getRect(find.byType(FileView));
    expect(_rail, findsNothing);
    expect(tester.getRect(_menu).right, preview.left - ChatHeader.end);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(FileView)), preview);
    toggleFiles(c);
    await tester.pump();
    expect(_rail, findsOneWidget);
    final rail = tester.getRect(_rail);
    await tester.pumpAndSettle();
    expect(tester.getRect(_rail), rail);
    await closeView(tester, d);
  }, variant: onMac);
}

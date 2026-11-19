import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/browser_pane.dart';
import 'package:nushi/chat_panes.dart';
import 'package:nushi/chat_view.dart';
import 'package:nushi/details_panel.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/sidebar.dart';
import 'package:nushi/slides.dart';
import 'package:nushi/transcript.dart';

import 'browser_fixture.dart' show browserFakes;
import 'fake_daemon.dart';
import 'harness.dart';
import 'right_panes_fixture.dart';

// No flicker at the line where the details rail tucks away or the panes
// lie over the transcript (ADR 0123): it's decided on widths alone, so
// each crossing flips it once and holding still never does, and nothing
// built again on the way.

const ({
  int browser,
  bool command,
  bool files,
  int previews,
  bool side,
  bool subagent,
})
_preview = (
  side: false,
  files: false,
  subagent: false,
  command: false,
  previews: 0,
  browser: 1,
);

/// Whether the rail is wanted shown now (its [Presence]'s say), whatever
/// its slide has reached; in a chat under 804 there's none (ADR 0092).
bool _railShown(WidgetTester tester) {
  final rail = find.ancestor(
    of: find.byType(DetailsPanel, skipOffstage: false),
    matching: find.byType(Presence, skipOffstage: false),
  );
  return rail.evaluate().isNotEmpty &&
      tester.widget<Presence>(rail.first).shown;
}

/// The panes lie over the transcript: it runs on under the preview.
bool _over(WidgetTester tester) =>
    _transcript(tester).right > tester.getRect(find.byType(BrowserPane)).left;

Rect _transcript(WidgetTester tester) => tester.getRect(
  find.byWidgetPredicate(
    (w) => w is Transcript && w.items == null && w.chat.id == 'c',
  ),
);

double _transcriptWidth(WidgetTester tester) => _transcript(tester).width;

/// Counts the rail's and the panes' flips, frame by frame, and holds the
/// layout's rules on each frame.
class _Watch {
  new(this.tester) : rail = _railShown(tester), over = _over(tester);

  final WidgetTester tester;
  bool rail;
  bool over;
  int railFlips = 0;
  int overFlips = 0;

  void frame() {
    expect(tester.takeException(), isNull);
    final r = _railShown(tester);
    final o = _over(tester);
    expect(r && o, isFalse, reason: 'the rail and the panes over, at once');
    if (!o) {
      expect(
        _transcriptWidth(tester),
        greaterThanOrEqualTo(ChatView.leastBesideWide),
      );
    }
    if (r != rail) railFlips++;
    if (o != over) overFlips++;
    rail = r;
    over = o;
  }
}

/// The preview's edge, grabbed and past the drag's slop.
Future<TestGesture> _grab(WidgetTester tester) async {
  final pane = tester.getRect(find.byType(BrowserPane));
  final drag = await tester.startGesture(
    Offset(pane.left + Resizable.edgeWidth / 2, pane.center.dy),
  );
  await drag.moveBy(const Offset(-20, 0));
  await tester.pump();
  return drag;
}

double _previewWidth(WidgetTester tester) =>
    tester.getRect(find.byType(BrowserPane)).width;

/// The preview dragged a point at a time until it's [width] wide.
Future<void> _dragTo(
  WidgetTester tester,
  TestGesture drag,
  double width,
) async {
  for (var i = 0; i < 400 && _previewWidth(tester) != width; i++) {
    await drag.moveBy(Offset(_previewWidth(tester) < width ? -1 : 1, 0));
    await tester.pump();
  }
  expect(_previewWidth(tester), width);
}

/// The widest the preview is with the rail still shown beside it.
double _railLine(WidgetTester tester) =>
    tester.getRect(find.byType(Pane)).width -
    DetailsPanel.width -
    ChatView.leastBesideWide;

void main() {
  setUpAll(loadFonts);
  setUp(browserFakes);

  // With the sidebar: the chat's pane is the window less 268; the preview
  // with the rail needs 1240 of it.
  final line = windowFor(1240, sidebar: true);

  testWidgets("dragged a point at a time across the rail's line and back, "
      '20 times: it flips at each crossing and nowhere else', (tester) async {
    final (d, fake) = await panesApp(
      tester,
      width: line + 30,
      sidebar: true,
      open: _preview,
    );
    final panel = tester.state(find.byType(DetailsPanel));
    int asks() =>
        fake.calls.whereType<GetFolderStatusRequest>().length +
        fake.calls.whereType<ListBranchesRequest>().length;
    final asked = asks();
    final drag = await _grab(tester);
    final watch = _Watch(tester);
    // The width where the rail goes: the chat's pane less the rail and the
    // transcript's least.
    final area = tester.getRect(find.byType(Pane)).width;
    final tucks = area - DetailsPanel.width - ChatView.leastBesideWide + 1;
    // To one point short of it.
    while (_previewWidth(tester) < tucks - 1) {
      await drag.moveBy(const Offset(-1, 0));
      await tester.pump();
      watch.frame();
    }
    expect(watch.railFlips, 0);
    for (var i = 0; i < 20; i++) {
      for (final by in const [-1.0, -1.0, 1.0, 1.0]) {
        await drag.moveBy(Offset(by, 0));
        await tester.pump();
        watch.frame();
      }
    }
    expect(watch.railFlips, 40);
    expect(watch.overFlips, 0);
    await drag.up();
    await tester.pump(const Duration(seconds: 2)); // the save
    await tester.pumpAndSettle();
    watch.frame();
    // The same panel all along, and it asked the daemon nothing again.
    expect(
      tester.state(find.byType(DetailsPanel, skipOffstage: false)),
      same(panel),
    );
    expect(asks(), asked);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('held at the line, or half a point from it, it never flips, '
      'and nothing is drawn once still', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: line,
      sidebar: true,
      open: _preview,
    );
    final drag = await _grab(tester);
    // At the line, the rail shown, and a point past it, tucked: held there
    // with the pointer moving half a point either way.
    final at = _railLine(tester);
    for (final (width, shown) in [(at, true), (at + 1, false)]) {
      await _dragTo(tester, drag, width);
      await tester.pumpAndSettle();
      expect(_railShown(tester), shown);
      final watch = _Watch(tester);
      for (var i = 0; i < 60; i++) {
        await drag.moveBy(Offset(i.isEven ? 0.5 : -0.5, 0));
        await tester.pump(const Duration(milliseconds: 16));
        watch.frame();
        expect(_previewWidth(tester), width);
      }
      expect(watch.railFlips, 0);
      await tester.pump(Motion.enter);
      await tester.pump();
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
    }
    await drag.up();
    await tester.pump(const Duration(seconds: 2));
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets("a pointer's sub-pixel jitter at the line flips it at most "
      'once', (tester) async {
    viewport(tester, Size(line, 900), ratio: 2);
    final (d, _) = await panesApp(
      tester,
      width: line,
      sidebar: true,
      open: _preview,
    );
    viewport(tester, Size(line, 900), ratio: 2);
    await tester.pumpAndSettle();
    final drag = await _grab(tester);
    // At the line's last shown width, then the pointer shaking by most of
    // a point across the half point where the width would round past it.
    await _dragTo(tester, drag, _railLine(tester));
    await drag.moveBy(const Offset(-0.05, 0));
    await tester.pump();
    final watch = _Watch(tester);
    for (var i = 0; i < 40; i++) {
      await drag.moveBy(Offset(i.isEven ? -0.9 : 0.9, 0));
      await tester.pump();
      watch.frame();
      expect(
        _previewWidth(tester),
        inInclusiveRange(_railLine(tester), _railLine(tester) + 1),
      );
    }
    expect(watch.railFlips, lessThanOrEqualTo(1));
    await drag.up();
    await tester.pump(const Duration(seconds: 2));
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('beside the transcript, a drag stops at its least: the pane '
      'never jumps under the header, and stays beside once let go', (
    tester,
  ) async {
    final (d, _) = await panesApp(
      tester,
      width: line,
      sidebar: true,
      open: _preview,
    );
    final area = tester.getRect(find.byType(Pane));
    final drag = await _grab(tester);
    for (var i = 0; i < 40; i++) {
      await drag.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(tester.getRect(find.byType(BrowserPane)).top, area.top);
      expect(tester.takeException(), isNull);
    }
    expect(_previewWidth(tester), area.width - ChatView.leastBesideWide);
    await drag.up();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_over(tester), isFalse);
    expect(paneWidths.value['browser'], area.width - ChatView.leastBesideWide);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('over the transcript, a drag either way flips nothing: the '
      'preview is at its least, and its edge stays there', (tester) async {
    // 600 for the chat's pane: under the preview's least and the
    // transcript's, 660.
    final (d, _) = await panesApp(
      tester,
      width: windowFor(600, sidebar: true),
      sidebar: true,
      open: _preview,
    );
    expect(_over(tester), isTrue);
    final at = tester.getRect(find.byType(BrowserPane));
    expect(at.width, 300);
    for (final by in [10.0, -10.0]) {
      final drag = await _grab(tester);
      final watch = _Watch(tester);
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(Offset(by, 0));
        await tester.pump();
        watch.frame();
      }
      await drag.up();
      await tester.pump();
      watch.frame();
      await tester.pumpAndSettle();
      watch.frame();
      expect(watch.overFlips, 0);
      expect(_over(tester), isTrue);
      expect(tester.getRect(find.byType(BrowserPane)), at);
    }
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('the window resized across both lines and back, a point at '
      'a time near each: each flips at each crossing', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: 900,
      sidebar: true,
      open: _preview,
    );
    final watch = _Watch(tester);
    // The rail's line at 1508, the panes' at 928 and where the preview
    // narrows, 1188: every point near each, where a flip could flicker,
    // and every 20th between, where the layout only glides.
    final lines = [
      line,
      windowFor(besideFrom([ChatPanes.browser])!, sidebar: true),
      windowFor(narrowFrom([ChatPanes.browser])!, sidebar: true),
    ];
    expect(lines, [1508, 928, 1188]);
    final widths = {
      for (var w = 900; w < 1600; w += 20) w,
      for (final at in lines)
        for (var w = at.toInt() - 8; w <= at.toInt() + 8; w++) w,
      1599,
    }.toList()..sort();
    for (final w in [...widths, ...widths.reversed.skip(1)]) {
      viewport(tester, Size(w.toDouble(), 900));
      await tester.pump();
      watch.frame();
    }
    // Each line crossed twice; the preview's narrowing flips nothing.
    expect(watch.railFlips, 2);
    expect(watch.overFlips, 2);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets("the sidebar dragged across the rail's line: it flips at each "
      'crossing', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: line + 10,
      sidebar: true,
      open: _preview,
    );
    // The sidebar's edge, at its right.
    final sidebar = tester.getRect(
      find
          .ancestor(of: find.byType(Sidebar), matching: find.byType(Resizable))
          .first,
    );
    final drag = await tester.startGesture(
      Offset(sidebar.right - Resizable.edgeWidth / 2, 400),
    );
    await drag.moveBy(const Offset(20, 0));
    await tester.pump();
    final watch = _Watch(tester);
    for (final by in [1.0, -1.0]) {
      for (var i = 0; i < 20; i++) {
        await drag.moveBy(Offset(by, 0));
        await tester.pump();
        watch.frame();
      }
    }
    expect(watch.railFlips, 2);
    await drag.up();
    await tester.pump(const Duration(seconds: 2));
    await closeView(tester, d);
  }, variant: onMac);
}

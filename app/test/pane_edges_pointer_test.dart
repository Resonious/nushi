import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat_header.dart';
import 'package:nushi/details_panel.dart';
import 'package:nushi/files_pane.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/settings.dart';

import 'harness.dart';
import 'right_panes_fixture.dart';

// The Files pane's edges in the app's layout (ADR 0123), driven by the
// pointer events the Mac's engine sends a trackpad and a mouse, the ones
// it sends when a release never reached it among them (ADR 0080, amended
// 2026-11-19): nothing moves an edge but a primary press that's held, and
// nothing a drag told the layout outlives it.

const PanesOpen _files = (
  side: false,
  files: true,
  subagent: false,
  command: false,
  previews: 1,
  browser: 0,
);

void main() {
  // The engine gives each press a pointer of its own, on the one mouse.
  var pointers = 10;
  TestPointer mouse() => TestPointer(pointers++, PointerDeviceKind.mouse, 0);

  Future<void> send(WidgetTester tester, PointerEvent e) async {
    await tester.sendEventToBinding(e);
    await tester.pump();
  }

  Finder edgeOf(String name) =>
      find.byWidgetPredicate((w) => w is Resizable && w.name == name);

  /// The middle of [name]'s edge, 200 down.
  Offset edge(WidgetTester tester, String name) {
    final r = tester.getRect(edgeOf(name));
    final left = tester.widget<Resizable>(edgeOf(name)).left;
    return Offset(
      left
          ? r.left + Resizable.edgeWidth / 2
          : r.right - Resizable.edgeWidth / 2,
      r.top + 200,
    );
  }

  /// Where the transcript, Files, its tree and the rail are.
  List<Rect> layout(WidgetTester tester) => [
    tester.getRect(find.byType(ChatHeader)),
    tester.getRect(find.byType(FilesPane)),
    tester.getRect(edgeOf('filesTree')),
    if (find.byType(DetailsPanel).evaluate().isNotEmpty)
      tester.getRect(find.byType(DetailsPanel)),
  ];

  Future<void> scroll(WidgetTester tester, Offset at) async {
    final pad = TestPointer(1, PointerDeviceKind.trackpad);
    await send(tester, pad.panZoomStart(at));
    for (var i = 1; i <= 6; i++) {
      await send(tester, pad.panZoomUpdate(at, pan: Offset(-30.0 * i, 0)));
    }
    await send(tester, pad.panZoomEnd());
  }

  /// A press on [name]'s edge, dragged left by [by] in steps of 10.
  Future<TestPointer> grab(
    WidgetTester tester,
    String name, {
    double by = 100,
  }) async {
    final press = mouse();
    final at = edge(tester, name);
    await send(tester, press.hover(at));
    await send(tester, press.down(at));
    for (var x = 10.0; x <= by; x += 10) {
      await send(tester, press.move(at - Offset(x, 0)));
    }
    return press;
  }

  testWidgets("a two-finger scroll over the Files pane's edge or its "
      "tree's moves nothing", (tester) async {
    final (d, _) = await panesApp(tester, width: 1900, open: _files);
    final before = layout(tester);
    await scroll(tester, edge(tester, 'filesPane'));
    await scroll(tester, edge(tester, 'filesTree'));
    await tester.pumpAndSettle();
    expect(layout(tester), before);
    expect(paneWidths.value, isEmpty);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('fingers resting, a click-drag of the Files edge: its release '
      'ends the drag, the fingers moving after move nothing', (tester) async {
    final (d, _) = await panesApp(tester, width: 1900, open: _files);
    final from = tester.getRect(find.byType(FilesPane)).width;
    final pad = TestPointer(1, PointerDeviceKind.trackpad);
    final at = edge(tester, 'filesPane');
    await send(tester, pad.panZoomStart(at));
    final press = await grab(tester, 'filesPane');
    await send(tester, press.up());
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(FilesPane)).width, from + 90);
    expect(paneWidths.value['filesPane'], from + 90);
    final after = layout(tester);
    for (var i = 1; i <= 6; i++) {
      await send(tester, pad.panZoomUpdate(at, pan: Offset(-30.0 * i, 0)));
    }
    await send(tester, pad.panZoomEnd());
    await tester.pumpAndSettle();
    expect(layout(tester), after);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets("the tree's edge: a hover mid-drag ends it, and the press's "
      'moves after move nothing', (tester) async {
    final (d, _) = await panesApp(tester, width: 1900, open: _files);
    final press = await grab(tester, 'filesTree', by: 60);
    await tester.sendEventToBinding(
      PointerHoverEvent(
        device: press.device,
        position: edge(tester, 'filesTree'),
      ),
    );
    await tester.pumpAndSettle();
    final saved = paneWidths.value['filesTree'];
    expect(saved, isNotNull);
    final after = layout(tester);
    final at = edge(tester, 'filesTree');
    for (var x = 10.0; x <= 80; x += 10) {
      await send(tester, press.move(at - Offset(x, 0)));
    }
    await send(tester, press.up());
    await tester.pumpAndSettle();
    expect(layout(tester), after);
    expect(paneWidths.value['filesTree'], saved);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('expanded mid-drag, then collapsed: dropped, the layout as '
      'before', (tester) async {
    final (d, _) = await panesApp(tester, width: 1900, open: _files);
    final before = layout(tester);
    final press = await grab(tester, 'filesPane', by: 300);
    expect(layout(tester), isNot(before));
    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();
    await send(tester, press.up());
    await tester.tap(find.byTooltip('Collapse'));
    await tester.pumpAndSettle();
    expect(paneWidths.value, isEmpty);
    expect(layout(tester), before);
    expect(tester.takeException(), isNull);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('closed mid-drag, then opened: dropped, the layout as before', (
    tester,
  ) async {
    final (d, _) = await panesApp(tester, width: 1900, open: _files);
    final before = layout(tester);
    final press = await grab(tester, 'filesTree', by: 60);
    filesChats.value = {};
    await tester.pumpAndSettle();
    await send(tester, press.up());
    filesChats.value = {'c'};
    await tester.pumpAndSettle();
    expect(paneWidths.value, isEmpty);
    expect(layout(tester), before);
    expect(tester.takeException(), isNull);
    await closeView(tester, d);
  }, variant: onMac);
}

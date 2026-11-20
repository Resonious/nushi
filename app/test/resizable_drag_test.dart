import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/theme/theme.dart';

import 'harness.dart';

void main() {
  /// A pane with its edge at its left, at the window's right, and what its
  /// drag told.
  Future<List<double?>> pane(WidgetTester tester, {double ratio = 1}) async {
    viewport(tester, const Size(1200, 600), ratio: ratio);
    final told = <double?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: const NushiTheme(Tokens.dark).toThemeData(),
        home: Align(
          alignment: Alignment.centerRight,
          child: Resizable(
            name: 'preview',
            initial: 400,
            min: 300,
            max: 700,
            left: true,
            onDrag: told.add,
            child: const SizedBox.expand(key: Key('pane')),
          ),
        ),
      ),
    );
    return told;
  }

  double width(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('pane'))).width;

  Future<TestGesture> grab(WidgetTester tester) async {
    final at = tester.getTopLeft(find.byKey(const Key('pane')));
    final drag = await tester.startGesture(
      at + const Offset(Resizable.edgeWidth / 2, 100),
    );
    // Past the drag's slop: the drag has begun.
    await drag.moveBy(const Offset(-20, 0));
    await tester.pump();
    return drag;
  }

  testWidgets('a drag is told in whole points, once each, and null as it '
      'ends', (tester) async {
    final told = await pane(tester);
    final drag = await grab(tester);
    final from = width(tester);
    told.clear();
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(-3, 0));
      await tester.pump();
    }
    expect(told, [for (var i = 1; i <= 10; i++) from + 3 * i]);
    expect(width(tester), from + 30);
    await drag.up();
    await tester.pump();
    expect(told.last, isNull);
    expect(paneWidths.value['preview'], from + 30);
    await tester.pump(const Duration(seconds: 2)); // the save
  });

  testWidgets("a pointer's sub-pixel jitter changes no width", (tester) async {
    final told = await pane(tester, ratio: 2);
    final drag = await grab(tester);
    final from = width(tester);
    told.clear();
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(Offset(i.isEven ? -0.3 : 0.3, 0));
      await tester.pump();
      expect(width(tester), from);
    }
    expect(told, isEmpty);
    await drag.up();
    await tester.pump();
    expect(told.whereType<double>(), isEmpty);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('it stops at its most and is told so once', (tester) async {
    final told = await pane(tester);
    final drag = await grab(tester);
    told.clear();
    await drag.moveBy(const Offset(-500, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-100, 0));
    await tester.pump();
    expect(told, [700]);
    expect(width(tester), 700);
    await drag.up();
    await tester.pump(const Duration(seconds: 2));
    expect(told, [700, null]);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/beside.dart';
import 'package:nushi/beside_fit.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/theme/theme.dart';

void main() {
  Widget beside(double cap) => MaterialApp(
    theme: const NushiTheme(Tokens.dark).toThemeData(),
    home: Beside(
      main: const SizedBox.expand(key: Key('main')),
      least: 360,
      panes: [
        SidePane.of(
          PaneSpec('preview', initial: 560, min: 300, cap: cap),
          child: const SizedBox.expand(key: Key('pane')),
        ),
      ],
    ),
  );

  Offset edge(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const Key('pane'))) + const Offset(2, 100);

  double width(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('pane'))).width;

  testWidgets('beside the chat, a pane with no cap stops where the chat '
      'keeps its least (ADR 0123)', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(beside(double.infinity));
    final drag = await tester.startGesture(edge(tester));
    await drag.moveBy(const Offset(-20, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-1300, 0));
    await tester.pump();
    expect(width(tester), 1400 - 360);
    await drag.up();
    await tester.pump();
    expect(width(tester), 1400 - 360);
    await tester.pump(const Duration(seconds: 2)); // the width's saved
  });

  testWidgets('narrowed for the chat, a pane drags narrower but no wider, '
      'and a drag that moves nothing saves nothing (ADR 0123)', (tester) async {
    // 800 less the chat's 360: the preview, saved at 700, is narrowed to
    // 440.
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    paneWidths.value = {'preview': 700};
    await tester.pumpWidget(beside(double.infinity));
    expect(width(tester), 440);
    var drag = await tester.startGesture(edge(tester));
    await drag.moveBy(const Offset(-20, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-1300, 0));
    await tester.pump();
    expect(width(tester), 440);
    await drag.up();
    await tester.pump();
    expect(width(tester), 440);
    expect(paneWidths.value['preview'], 700);
    // Narrower is the user's to give: that's saved.
    drag = await tester.startGesture(edge(tester));
    await drag.moveBy(const Offset(20, 0)); // the slop
    await tester.pump();
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(width(tester), 400);
    expect(paneWidths.value['preview'], 400);
    await tester.pump(const Duration(seconds: 2)); // the width's saved
  });

  testWidgets('narrowed for the chat, the rest take back what a pane '
      'dragged narrower gives, as it is dragged (ADR 0123)', (tester) async {
    // 920 less the chat's 360: Files keeps its 260, the preview gives 260.
    tester.view.physicalSize = const Size(920, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: const NushiTheme(Tokens.dark).toThemeData(),
        home: Beside(
          main: const SizedBox.expand(key: Key('main')),
          least: 360,
          panes: [
            SidePane.of(
              const PaneSpec('files', initial: 260, min: 200, cap: 480),
              child: const SizedBox.expand(key: Key('files body')),
            ),
            SidePane.of(
              const PaneSpec(
                'preview',
                initial: 560,
                min: 300,
                cap: double.infinity,
              ),
              child: const SizedBox.expand(key: Key('pane')),
            ),
          ],
        ),
      ),
    );
    double of(String key) => tester.getSize(find.byKey(Key(key))).width;
    expect([of('files body'), of('pane')], [260, 300]);
    final drag = await tester.startGesture(
      tester.getTopLeft(find.byKey(const Key('files body'))) +
          const Offset(2, 100),
    );
    await drag.moveBy(const Offset(20, 0)); // the slop
    await tester.pump();
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    // Mid-drag: the preview has the 40 back, the chat still its 360.
    expect([of('files body'), of('pane')], [220, 340]);
    expect(of('main'), 360);
    await drag.up();
    await tester.pump();
    expect([of('files body'), of('pane')], [220, 340]);
    expect(paneWidths.value, {'files': 220});
    await tester.pump(const Duration(seconds: 2)); // the width's saved
  });

  testWidgets('over the chat, a pane is at its least and its edge stops '
      'there', (tester) async {
    // 600 less the chat's 360 is under the pane's least: it lies over it.
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(beside(double.infinity));
    expect(width(tester), 300);
    final drag = await tester.startGesture(edge(tester));
    await drag.moveBy(const Offset(-20, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-1300, 0));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(width(tester), 300);
    expect(paneWidths.value.containsKey('preview'), isFalse);
    await tester.pump(const Duration(seconds: 2)); // the width's saved
  });

  testWidgets('one with a cap keeps the chat its least width', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(beside(1000));
    final drag = await tester.startGesture(edge(tester));
    await drag.moveBy(const Offset(-20, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-900, 0));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(width(tester), 1200 - 360);
    await tester.pump(const Duration(seconds: 2)); // the width's saved
  });

  testWidgets('let go at its most in a room that is not whole, it stays '
      'beside the chat', (tester) async {
    // 1300.5 wide: beside the chat its most is 940.5, and rounded to the
    // nearest point it would leave the chat 359.5, under its least.
    tester.view.physicalSize = const Size(2601, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(beside(double.infinity));
    final drag = await tester.startGesture(edge(tester));
    await drag.moveBy(const Offset(-20, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-1300, 0));
    await tester.pump();
    expect(width(tester), 1300.5 - 360);
    await drag.up();
    await tester.pump();
    expect(paneWidths.value['preview'], 940);
    expect(width(tester), 940);
    expect(tester.getSize(find.byKey(const Key('main'))).width, 360.5);
    await tester.pump(const Duration(seconds: 2)); // the width's saved
  });

  group('a pane gone mid-drag leaves nothing deciding for it', () {
    // 1000 wide: the pane at its 300 leaves the view 500 beside the 200 of
    // the rail, which shows; dragged to 550, the view would keep 250 and
    // the rail tucks away.
    final open = ValueNotifier(true);
    final cover = ValueNotifier<String?>(null);
    Widget app() => MaterialApp(
      theme: const NushiTheme(Tokens.dark).toThemeData(),
      home: ListenableBuilder(
        listenable: Listenable.merge([open, cover]),
        builder: (context, _) => Beside(
          main: const SizedBox.expand(),
          least: 300,
          cover: cover.value,
          details: SidePane.fixed(
            'details',
            width: 200,
            child: const SizedBox.expand(key: Key('rail')),
          ),
          panes: [
            if (open.value)
              SidePane.of(
                const PaneSpec('p', initial: 300, min: 200, cap: 800),
                child: const SizedBox.expand(key: Key('pane')),
              ),
          ],
        ),
      ),
    );
    Finder rail() => find.byKey(const Key('rail'));

    Future<TestGesture> tuck(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      open.value = true;
      cover.value = null;
      await tester.pumpWidget(app());
      expect(rail(), findsOneWidget);
      final drag = await tester.startGesture(edge(tester));
      await drag.moveBy(const Offset(-20, 0));
      await tester.pump();
      await drag.moveBy(const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(width(tester), 550);
      expect(rail(), findsNothing);
      return drag;
    }

    testWidgets('closed while its edge is held', (tester) async {
      final drag = await tuck(tester);
      open.value = false; // a key, or the agent
      await tester.pumpAndSettle(); // gone, its edge with it
      await drag.up();
      await tester.pumpAndSettle();
      expect(paneWidths.value, isEmpty);
      open.value = true;
      await tester.pumpAndSettle();
      expect(width(tester), 300);
      expect(rail(), findsOneWidget);
    });

    testWidgets('over all while its edge is held', (tester) async {
      final drag = await tuck(tester);
      cover.value = 'p'; // Expand, from a key
      await tester.pumpAndSettle();
      await drag.up();
      cover.value = null;
      await tester.pumpAndSettle();
      expect(paneWidths.value, isEmpty);
      expect(width(tester), 300);
      expect(rail(), findsOneWidget);
    });
  });

  testWidgets('a platform view keeps clear of the edge, on whichever side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (left, top, inset) in [
      (true, false, const EdgeInsets.only(left: Resizable.edgeWidth)),
      (false, false, const EdgeInsets.only(right: Resizable.edgeWidth)),
      (false, true, const EdgeInsets.only(top: Resizable.edgeWidth)),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: const NushiTheme(Tokens.dark).toThemeData(),
          home: Align(
            alignment: Alignment.topLeft,
            child: Resizable(
              name: 'test',
              initial: 300,
              min: 100,
              max: 500,
              left: left,
              top: top,
              child: const ColoredBox(
                key: Key('pane'),
                color: Color(0xFF000000),
                child: ClearOfEdge(child: SizedBox.expand(key: Key('view'))),
              ),
            ),
          ),
        ),
      );
      final pane = tester.getRect(find.byKey(const Key('pane')));
      expect(
        tester.getRect(find.byKey(const Key('view'))),
        inset.deflateRect(pane),
      );
    }
    // Outside a pane it fills its place.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ClearOfEdge(child: SizedBox.expand(key: Key('view'))),
      ),
    );
    expect(
      tester.getRect(find.byKey(const Key('view'))),
      Offset.zero & const Size(800, 600),
    );
  });
}

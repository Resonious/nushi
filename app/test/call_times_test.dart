import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide LiveText;
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/call_times.dart';
import 'package:nushi/clock.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/live_text.dart';
import 'package:nushi/main.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/status.dart';
import 'package:nushi/theme/tokens.dart';
import 'package:nushi/tool_calls.dart';

import 'fake_daemon.dart';
import 'harness.dart';

/// [fixtureNow] less [s] seconds, as the daemon sends a time.
Int64 _ago(num s) => Int64(
  fixtureNow
      .subtract(Duration(milliseconds: (s * 1000).round()))
      .millisecondsSinceEpoch,
);

/// A command run [from] seconds ago that ended [to] seconds ago (running
/// while [to] is null).
Item _call(String id, String title, num from, num? to) => Item(
  id: id,
  kind: ItemKind.ITEM_KIND_TOOL_CALL,
  toolKind: 'execute',
  title: title,
  status: to == null ? 'in_progress' : 'completed',
  started: _ago(from),
  ended: to == null ? null : _ago(to),
);

Item _said(String id, String text) =>
    Item(id: id, kind: ItemKind.ITEM_KIND_AGENT_MESSAGE, text: text);

/// A transcript with a call of under a second, one of 12 seconds, a run of
/// three, and a call that runs.
List<Item> _items() => [
  Item(
    id: 'u',
    kind: ItemKind.ITEM_KIND_USER_MESSAGE,
    text: 'Tidy the store package and check it.',
  ),
  Item(
    id: 'r',
    kind: ItemKind.ITEM_KIND_TOOL_CALL,
    toolKind: 'read',
    title: 'Read internal/store/store.go',
    paths: ['internal/store/store.go'],
    status: 'completed',
    started: _ago(600),
    ended: _ago(599.6),
  ),
  _said('m1', 'The tests first.'),
  _call('t', 'go test ./internal/store/...', 590, 578),
  _said('m2', 'Now the lint, the vet and the build.'),
  _call('g1', 'make lint', 570, 540),
  _call('g2', 'go vet ./...', 538, 530),
  _call('g3', 'go build ./cmd/nushid', 528, 506),
  _said('m4', 'And the whole suite, with a long name to see it give way.'),
  _call(
    'c',
    'go test -race -count=1 ./internal/features/chats/... ./internal/e2e/...',
    12,
    null,
  ),
];

/// Renders the transcript at [size] in [brightness] as [name].
Future<void> _window(
  WidgetTester tester,
  Size size,
  Brightness brightness,
  String name,
) async {
  viewport(tester, size, brightness: brightness);
  showDetails.value = false;
  final c = chat('c', 'claude', 'Tidy the store package');
  final fake = FakeDaemon([c])
    ..answer = (input) => input is GetChatRequest
        ? GetChatResponse(chat: c, items: _items())
        : null;
  final d = await fake.connect(tester);
  d.select('c');
  await tester.pumpWidget(NushiApp(daemon: d));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text('12s'), findsWidgets); // the run's and the running call's
  expect(find.text('1m 04s'), findsOne); // the run's span
  expectTextInside(tester, size.width);
  await render(tester, find.byType(NushiApp), name);
  await tester.pumpWidget(const SizedBox());
  d.dispose();
}

void main() {
  setUpAll(loadFonts);
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('nushi/fonts'),
          (_) async => <String>[],
        ),
  );

  test('times read as a row shows them', () {
    expect(elapsed(const Duration(seconds: 12)), '12s');
    expect(elapsed(const Duration(seconds: 64)), '1m 04s');
    // Under a second, replayed (no times), or never ended: nothing.
    expect(callTime(_call('a', 'ls', 1, 0.4)), isNull);
    expect(callTime(Item(status: 'completed')), isNull);
    expect(callTime(Item(status: 'failed', started: _ago(5))), isNull);
    expect(callTime(_call('a', 'ls', 72, 8)), const Duration(seconds: 64));
    // Running, to now; its turn's end stops it.
    expect(callTime(_call('a', 'ls', 12, null)), const Duration(seconds: 12));
    expect(
      callTime(_call('a', 'ls', 12, null)..ended = _ago(2)),
      const Duration(seconds: 10),
    );
  });

  test("a run's time is its first call's start to its last's end", () {
    final run = [
      _call('a', 'one', 60, 50),
      Item(id: 'b', status: 'completed'), // replayed: left out
      _call('c', 'two', 40, 4),
    ];
    expect(runTime(run), const Duration(seconds: 56));
    expect(
      runTime([...run, _call('d', 'three', 3, null)]),
      const Duration(seconds: 60),
    );
    expect(runTime([Item(id: 'b', status: 'completed')]), isNull);
  });

  testWidgets('a running call ticks on the one clock; one ended stops', (
    tester,
  ) async {
    var now = fixtureNow;
    clock = () => now;
    final calls = ValueNotifier([_call('c', 'sleep 30', 12, null)]);
    addTearDown(calls.dispose);
    await tester.pumpWidget(
      themed(
        ValueListenableBuilder(
          valueListenable: calls,
          builder: (context, c, _) => Column(
            children: [
              ToolCallView(c.single),
              RunView([...c, c.single]),
            ],
          ),
        ),
      ),
    );
    expect(find.text('12s'), findsNWidgets(2));
    expect(secondClock.ticking, isTrue);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('13s'), findsNWidgets(2));
    calls.value = [
      calls.value.single.deepCopy()
        ..status = 'completed'
        ..ended = Int64(now.millisecondsSinceEpoch),
    ];
    await tester.pump();
    expect(secondClock.ticking, isFalse);
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('13s'), findsNWidgets(2));
  });

  testWidgets('a live time scrolled out of view waits', (tester) async {
    viewport(tester, const Size(400, 300));
    var built = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      themed(
        SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              LiveText(
                () => '${++built}',
                live: true,
                style: const TextStyle(),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(built, 2);
    scroll.jumpTo(1000);
    await tester.pump();
    final hidden = built;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(built, hidden);
    scroll.jumpTo(0);
    await tester.pump(const Duration(seconds: 1));
    expect(built, hidden + 1);
  });

  testWidgets('narrow, the title gives way and the time stays at the end', (
    tester,
  ) async {
    viewport(tester, const Size(800, 400));
    final width = ValueNotifier(266.0);
    addTearDown(width.dispose);
    final long = _call('c', 'go test -race ./internal/features/...', 64, null);
    final run = [_call('a', 'make lint', 90, 70), long];
    for (final tokens in [Tokens.dark, Tokens.light]) {
      await tester.pumpWidget(
        themed(
          tokens: tokens,
          ValueListenableBuilder(
            valueListenable: width,
            builder: (context, w, _) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: w,
                child: Column(children: [ToolCallView(long), RunView(run)]),
              ),
            ),
          ),
        ),
      );
      // A row that overflows fails the test.
      for (var w = 266.0; w >= 120; w -= 2) {
        width.value = w;
        await tester.pump();
        final row = tester.getRect(find.byType(ToolCallView));
        final time = find.descendant(
          of: find.byType(ToolCallView),
          matching: find.text('1m 04s'),
        );
        // The subagent's line keeps its time and tokens before its words.
        if (w >= 200) {
          expect(time, findsOne, reason: 'at $w');
          expect(tester.getRect(time).right, closeTo(row.right - 12, 12));
          expect(tester.getSize(time).width, lessThan(callTimeRoom));
        }
      }
      width.value = 266;
      await tester.pump();
    }
    Collapsible.opened.clear();
  });

  for (final (size, label) in [
    (const Size(1700, 1000), 'wide'),
    (const Size(720, 1000), 'narrow'),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('the times in a transcript, $label, ${brightness.name}', (
        tester,
      ) async {
        await _window(
          tester,
          size,
          brightness,
          'call_times_${label}_${brightness.name}',
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }
}

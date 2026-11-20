import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/controls.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/items.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/tool_calls.dart';
import 'package:nushi/transcript_entries.dart';
import 'package:nushi/workflow_card.dart';
import 'package:nushi/workflows.dart';

import 'fake_daemon.dart';
import 'harness.dart';

/// A workflow's call, its run in [state].
Item workflowCall(String state, {bool stalled = false, String id = 'wf'}) {
  final ended = state != 'running' && state.isNotEmpty;
  return Item(
    id: id,
    kind: ItemKind.ITEM_KIND_TOOL_CALL,
    tool: 'Workflow',
    title: 'Workflow',
    status: 'completed',
    text: 'Workflow launched in background. Task ID: w1',
    workflow: Workflow(
      runId: 'wf_769a004c-2aa',
      name: 'review-changes',
      description: 'Review the diff from five angles, then verify',
      state: state,
      end: switch (state) {
        'done' => 'completed',
        'stopped' => 'killed',
        'failed' => 'failed',
        'unknown' => 'paused',
        _ => '',
      },
      summary: state == 'failed' ? 'Error: the script threw' : '',
      started: msAgo(const Duration(minutes: 4, seconds: 12)),
      ended: ended ? msAgo(Duration.zero) : null,
      active: stalled ? msAgo(const Duration(hours: 1, minutes: 5)) : null,
      stalled: stalled,
      // While it runs, as workflow_pane_test's agents are: the pane's
      // tree and the card count alike.
      agents: ended ? 12 : 10,
      done: ended ? 12 : 6,
      failed: ended ? 0 : 1,
      phases: [
        WorkflowPhase(title: 'Map', started: 2, done: 2),
        WorkflowPhase(
          title: 'Review',
          started: 7,
          done: ended ? 7 : 3,
          failed: ended ? 0 : 1,
        ),
        if (ended) WorkflowPhase(title: 'Verify', started: 3, done: 3),
      ],
      running: ended ? null : ['review:ui', 'review:perf', 'review:api'],
      runningCount: ended ? 0 : 3,
      tokens: Int64(ended ? 96500 : 61200),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Item call, {
  Tokens tokens = Tokens.dark,
  double width = 640,
}) async {
  viewport(tester, Size(width, 140));
  await tester.pumpWidget(
    themed(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: WorkflowCard(call, ChatState('c', '/x'), still: true),
        ),
      ),
      tokens: tokens,
    ),
  );
}

void main() {
  setUpAll(loadFonts);
  setUp(() => Shine.stopAt = 0.3);
  tearDown(() => Shine.stopAt = null);

  test('each state in words', () {
    expect(
      workflowState(workflowCall('running').workflow),
      'Review 4/7 · 3 running · 61.2k tokens · 4m 12s',
    );
    expect(
      workflowState(workflowCall('done').workflow),
      '12 agents · 96.5k tokens · 4m 12s', // its check says done
    );
    expect(
      workflowState(workflowCall('failed').workflow),
      startsWith('failed'),
    );
    expect(
      workflowState(workflowCall('stopped').workflow),
      startsWith('stopped'),
    );
    expect(
      workflowState(workflowCall('unknown').workflow),
      startsWith('ended'),
    );
    expect(
      workflowState(workflowCall('running', stalled: true).workflow),
      'no activity for 1h · Review 4/7 · 3 running · 61.2k tokens',
    );
    expect(
      workflowState(Workflow(state: 'running', started: msAgo(Duration.zero))),
      'starting · 0s',
    );
    // A short line's choices: its count, then its tokens, give way.
    expect(workflowStates(workflowCall('running').workflow), [
      'Review 4/7 · 3 running · 61.2k tokens · 4m 12s',
      'Review 4/7 · 61.2k tokens · 4m 12s',
      'Review 4/7 · 4m 12s',
    ]);
    expect(
      phasesLine(workflowCall('running').workflow),
      'Map 2/2 · Review 4/7',
    );
    expect(
      runningMore(
        Workflow(running: ['review:ui', 'review:perf'], runningCount: 3),
      ),
      1,
    );
    expect(workflowEndWords(workflowCall('unknown').workflow), 'paused');
    expect(
      workflowEndWords(workflowCall('failed').workflow),
      'Error: the script threw',
    );
  });

  testWidgets('a followed run is a card; one not followed a plain call', (
    tester,
  ) async {
    final fake = FakeDaemon([]);
    final d = await fake.connect(tester);
    final chat = ChatState('c', '/x');
    final plain = workflowCall('')..clearWorkflow();
    final notYet = workflowCall('');
    for (final (it, card) in [
      (workflowCall('running'), true),
      (plain, false),
      (notYet, false),
    ]) {
      await tester.pumpWidget(
        themed(ItemView(it, chat, d, live: false, still: true)),
      );
      expect(find.byType(WorkflowCard), card ? findsOneWidget : findsNothing);
      expect(find.byType(ToolCallView), card ? findsNothing : findsOneWidget);
    }
    // A card joins no run of tool calls.
    final entries = transcriptEntries([
      Item(id: 'a', kind: ItemKind.ITEM_KIND_TOOL_CALL, title: 'Read'),
      workflowCall('running'),
      Item(id: 'b', kind: ItemKind.ITEM_KIND_TOOL_CALL, title: 'Read'),
    ]);
    expect(entries.length, 3);
    await closeView(tester, d);
  });

  testWidgets('its state, mark and chevron end the line; long text is cut', (
    tester,
  ) async {
    final call = workflowCall('running');
    call.workflow
      ..name = 'review-${'very-long-name-' * 6}'
      ..description = '長い説明 ' * 30
      ..running.add('🙂' * 40);
    await _pump(tester, call, width: 392);
    expectTextInside(tester, 392);
    final card = tester.getRect(find.byType(WorkflowCard));
    final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
    expect(chevron.right, greaterThan(card.right - 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('it says each thing once: its phase only in its state', (
    tester,
  ) async {
    await _pump(tester, workflowCall('running'));
    expect(find.textContaining('Review 4/7'), findsOne);
    expect(find.textContaining('Map 2/2'), findsNothing);
    expect(find.textContaining('review:ui'), findsNothing);
    expect(find.textContaining('five angles'), findsNothing);
    // One line, as a subagent's row.
    expect(tester.getSize(find.byType(WorkflowCard)).height, 36);
  });

  testWidgets('a click opens its pane, which lights it', (tester) async {
    final chat = ChatState('c', '/x');
    await tester.pumpWidget(
      themed(WorkflowCard(workflowCall('running'), chat, still: true)),
    );
    final t = NushiTheme.of(tester.element(find.byType(WorkflowCard))).t;
    Color? fill() => tester
        .widget<Tap>(
          find.descendant(
            of: find.byType(WorkflowCard),
            matching: find.byType(Tap),
          ),
        )
        .fill;
    expect(fill(), t.subagentTint);
    await tester.tap(find.byType(WorkflowCard));
    await tester.pump();
    expect(chat.pane.value, 'wf');
    expect(fill(), t.accentSoft); // lit while its pane is open
  });

  for (final (name, tokens) in [
    ('dark', Tokens.dark),
    ('light', Tokens.light),
  ]) {
    testWidgets('a narrow workflow card: the state on a line of its own '
        '($name)', (tester) async {
      await _pump(tester, workflowCall('running'), tokens: tokens, width: 392);
      expect(find.text('Map 2/2 · Review 4/7'), findsNothing);
      await expectLater(
        find.byType(WorkflowCard),
        matchesGoldenFile('goldens/workflow_card_narrow_$name.png'),
      );
    });
    for (final (state, stalled) in [
      ('running', false),
      ('running', true),
      ('done', false),
      ('failed', false),
      ('stopped', false),
      ('unknown', false),
    ]) {
      final label = stalled ? 'stalled' : state;
      testWidgets('a workflow card, $label ($name)', (tester) async {
        await _pump(
          tester,
          workflowCall(state, stalled: stalled),
          tokens: tokens,
        );
        await expectLater(
          find.byType(WorkflowCard),
          matchesGoldenFile('goldens/workflow_card_${label}_$name.png'),
        );
      });
    }
  }
}

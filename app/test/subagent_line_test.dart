import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/subagents.dart';

import 'harness.dart';

void main() {
  testWidgets('a subagent line keeps its state at the end, by its mark', (
    tester,
  ) async {
    final run = (
      call: Item(
        id: 'a',
        kind: ItemKind.ITEM_KIND_TOOL_CALL,
        agent: 'general-purpose',
        title: 'Verify the steps',
        status: 'completed',
        subagent: Subagent(state: 'done', tokens: Int64(182400)),
      ),
      items: <Item>[],
    );
    await tester.pumpWidget(
      themed(SubagentLine(run, ChatState('c', '/x'), still: true)),
    );
    // Done says no word: its check does (#106).
    expect(find.textContaining('done'), findsNothing);
    final state = tester.getRect(find.text('182k tokens'));
    final chevron = tester.getRect(find.byIcon(paneIcon));
    // The state, its mark (a check) and the chevron end the line, not its
    // middle.
    expect(chevron.left - state.right, lessThan(40));
    final line = tester.getRect(find.byType(SubagentLine));
    expect(chevron.right, greaterThan(line.right - 20));
  });

  testWidgets('a running subagent whose start isn’t known ends its words '
      'with no dot', (tester) async {
    final run = (
      call: Item(
        id: 'a',
        kind: ItemKind.ITEM_KIND_TOOL_CALL,
        agent: 'general-purpose',
        title: 'Verify the steps',
        status: 'in_progress',
        subagent: Subagent(state: 'running'),
      ),
      items: <Item>[],
    );
    await tester.pumpWidget(
      themed(
        SizedBox(width: 900, child: SubagentLine(run, ChatState('c', '/x'))),
      ),
    );
    expect(subagentTime(run), '');
    final texts = [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
    ];
    expect(texts.where((t) => t.contains('·')), isEmpty, reason: '$texts');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a live line ticks each second; one done no longer does', (
    tester,
  ) async {
    var built = 0;
    Widget line({required bool live}) => Directionality(
      textDirection: TextDirection.ltr,
      child: LiveText(() => '${++built}', live: live, style: const TextStyle()),
    );
    await tester.pumpWidget(line(live: true));
    await frames(tester, 2, const Duration(seconds: 1));
    expect(built, 3);
    await tester.pumpWidget(line(live: false));
    final done = built;
    await frames(tester, 5, const Duration(seconds: 1));
    expect(built, done);
    await tester.pumpWidget(line(live: true)); // live again: ticks again
    await tester.pump(const Duration(seconds: 1));
    expect(built, done + 2);
  });
}

// ChatFind on its own (ADR 0144): the daemon's counts of the matches
// above what's loaded, the transcript's matches as laid out, and where a
// step lands once a far match's part is in.
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/chat_find.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';

/// A chat whose loaded part is items l1 and l2, with 100 items above, and
/// its find, whose daemon answers [far], and the entries laid out (an
/// item's id to its entry's key).
(ChatFind, Map<String, String>) _find(List<ChatMatch> far) {
  final chat = ChatState('c', '/x')
    ..older = 100
    ..items.addAll([Item(id: 'l1'), Item(id: 'l2')]);
  final laid = <String, String>{'l1': 'l1', 'l2': 'l2'};
  final f = chat.find
    ..entryOf = ((id) => laid[id])
    ..ask = (r, signal) async => FindInChatResponse(matches: far);
  return (f, laid);
}

/// Types [q] and lets the daemon answer.
Future<void> _type(WidgetTester tester, ChatFind f, String q) async {
  f
    ..open()
    ..query = q;
  await tester.pump(ChatFind.pause);
  await tester.pump();
}

void main() {
  testWidgets('a step to the second of a run of calls above lands on that '
      'call’s match, not the run’s first', (tester) async {
    final (f, laid) = _find([
      ChatMatch(itemId: 'c1', count: 1),
      ChatMatch(itemId: 'c2', count: 1),
    ]);
    await _type(tester, f, 'needle');
    f.found(['l1 0']);
    expect(f.hits, ['far c1 0', 'far c2 0', 'l1 0']);
    expect(f.current, 'l1 0');
    f.step(-1);
    expect(f.pending, 'far c2 0');
    // Its page comes: c1 and c2 are one run of calls, keyed by c1, its
    // marks c1's then c2's.
    laid.addAll({'c1': 'c1', 'c2': 'c1'});
    f.found(['c1 0', 'c1 1', 'l1 0']);
    expect(f.current, 'c1 1');
    f.step(-1);
    expect(f.current, 'c1 0', reason: 'c1’s match, not skipped');
  });

  testWidgets('a step to a subagent’s step lands past the call’s own '
      'matches', (tester) async {
    final (f, laid) = _find([
      ChatMatch(itemId: 'call', count: 2),
      ChatMatch(itemId: 'step', count: 1),
    ]);
    await _type(tester, f, 'needle');
    f
      ..found(['l1 0'])
      ..step(-1);
    expect(f.pending, 'far step 0');
    laid.addAll({'call': 'agent call', 'step': 'agent call'});
    f.found(['agent call 0', 'agent call 1', 'agent call 2', 'l1 0']);
    expect(f.current, 'agent call 2');
  });

  for (final by in [1, -1]) {
    testWidgets('with nothing loaded to go to, the first step '
        '(${by > 0 ? '⏎' : '⇧⏎'}) shows the nearest match above, which '
        'typing made current', (tester) async {
      final (f, _) = _find([
        ChatMatch(itemId: 'a', count: 1),
        ChatMatch(itemId: 'b', count: 1),
        ChatMatch(itemId: 'c', count: 1),
      ]);
      await _type(tester, f, 'needle');
      f.found(const []);
      expect(f.count, '3 of 3');
      expect(f.current, 'far c 0');
      f.step(by);
      expect(f.current, 'far c 0', reason: 'not moved off unseen');
      expect(f.pending, 'far c 0', reason: 'its part loads');
      expect(f.stepped, isTrue);
      f.step(by);
      expect(f.current, by > 0 ? 'far a 0' : 'far b 0');
    });
  }
}

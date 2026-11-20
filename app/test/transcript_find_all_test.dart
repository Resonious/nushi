// ⌘F in a long chat finds in all of it (ADR 0144): the daemon counts the
// matches above what's loaded (FindInChat), a step to one loads its part
// and lands on it, a changed query cancels the search before, and a chat
// that grows is counted as it goes.
import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/chat_find.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/main.dart';
import 'package:nushi/settings.dart';

import 'fake_daemon.dart';
import 'harness.dart';
import 'long_chat.dart';
import 'paged_chat.dart';

/// The window on a long chat (100 turns, over a thousand items) whose
/// fifth turn's reply, far above what's loaded, and 98th, loaded, say
/// "needle".
Future<(Daemon, PagedChat, FakeDaemon)> _window(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
  Brightness brightness = Brightness.dark,
}) async {
  viewport(tester, size, brightness: brightness);
  showDetails.value = false;
  final c = chat('c', 'claude', 'A long chat');
  final items = longChat('c', turns: 100);
  for (final n in [5, 98]) {
    final i = items.indexWhere((it) => it.id == 'c-a$n');
    items[i] = items[i].deepCopy()
      ..text = 'Turn $n left a needle in the upload path.\n\n${items[i].text}';
  }
  final paged = PagedChat(c, items);
  final fake = FakeDaemon([c])..answer = paged.answer;
  final d = await fake.connect(tester);
  d.select('c');
  await tester.pumpWidget(NushiApp(daemon: d));
  await _settle(tester);
  return (d, paged, fake);
}

Future<void> _settle(WidgetTester tester) async {
  await frames(tester, 40, const Duration(milliseconds: 16));
}

ChatState _chat(Daemon d) => d.chats['c']!;

/// Whether [text]'s first match shows in the transcript.
bool _shows(WidgetTester tester, String text) {
  final list = tester.getRect(find.byType(SelectionArea));
  final hit = tester.getRect(
    find.textContaining(text, findRichText: true).first,
  );
  return hit.top >= list.top && hit.bottom <= list.bottom;
}

void main() {
  setUpAll(loadFonts);

  testWidgets('a match above what’s loaded is counted, nothing loaded and no '
      'Load all; the typed query goes to the match that’s loaded', (
    tester,
  ) async {
    final (d, paged, _) = await _window(tester);
    final c = _chat(d);
    final older = c.older;
    c.find
      ..open()
      ..query = 'needle';
    await _settle(tester);
    final asked = paged.asked.whereType<FindInChatRequest>().single;
    expect(asked.text, 'needle');
    expect(asked.before, c.items.first.id, reason: 'the rest it finds');
    expect(c.find.count, '2 of 2');
    expect(c.find.whole, isTrue);
    expect(paged.pages, isEmpty);
    expect(c.older, older);
    expect(find.text('Load all'), findsNothing);
    expect(find.text('Searching loaded messages · '), findsNothing);
    expect(_shows(tester, 'Turn 98 left a needle'), isTrue);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('a step to a match above loads its part, lands on it and '
      'shows it; stepping on wraps round', (tester) async {
    final (d, paged, _) = await _window(tester);
    final c = _chat(d);
    c.find
      ..open()
      ..query = 'needle';
    await _settle(tester);
    c.find.step(1); // past the last: round to the first, far above
    expect(ChatFind.farItem(c.find.current), 'c-a5');
    await _settle(tester);
    await _settle(tester);
    final page = paged.pages.first;
    expect(page.through, 'c-a5', reason: 'one page reaching back to it');
    expect(c.items.any((it) => it.id == 'c-a5'), isTrue);
    expect(c.find.count, '1 of 2');
    expect(ChatFind.farItem(c.find.current), isNull);
    expect(_shows(tester, 'Turn 5 left a needle'), isTrue);
    c.find.step(1);
    await _settle(tester);
    expect(c.find.count, '2 of 2');
    expect(_shows(tester, 'Turn 98 left a needle'), isTrue);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('a page loaded by scrolling up keeps the count and the '
      'current match', (tester) async {
    final (d, _, _) = await _window(tester);
    final c = _chat(d);
    c.find
      ..open()
      ..query = 'needle';
    await _settle(tester);
    final current = c.find.current;
    await d.loadOlder(c);
    await _settle(tester);
    expect(c.find.count, '2 of 2');
    expect(c.find.current, current);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('a query changed while the daemon searches cancels that '
      'search, and only the new one counts', (tester) async {
    final (d, paged, fake) = await _window(tester);
    final c = _chat(d);
    final hold = paged.holdFind = Completer<void>();
    c.find
      ..open()
      ..query = 'needl';
    await tester.pump(ChatFind.pause + const Duration(milliseconds: 10));
    expect(c.find.searching, isTrue);
    c.find.query = 'Turn 5 left';
    await tester.pump(ChatFind.pause + const Duration(milliseconds: 10));
    expect(fake.cancelled.whereType<FindInChatRequest>().map((r) => r.text), [
      'needl',
    ]);
    hold.complete();
    await _settle(tester);
    expect(c.find.count, '1 of 1');
    expect(ChatFind.farItem(c.find.current), 'c-a5');
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('a chat that grows while find is open counts what comes, the '
      'current match kept', (tester) async {
    final (d, paged, fake) = await _window(tester);
    final c = _chat(d);
    c.find
      ..open()
      ..query = 'needle';
    await _settle(tester);
    final current = c.find.current;
    final it = Item(
      id: 'c-new',
      kind: ItemKind.ITEM_KIND_AGENT_MESSAGE,
      text: 'One more needle, at the end.',
    );
    fake.emit(
      EventsResponse(
        chatId: 'c',
        seq: Int64(1),
        item: ItemEvent(item: it, index: paged.items.length),
      ),
    );
    paged.items.add(it);
    await _settle(tester);
    expect(c.find.count, '2 of 3');
    expect(c.find.current, current);
    expect(
      paged.asked.whereType<FindInChatRequest>(),
      hasLength(1),
      reason: 'what grows is loaded: the transcript finds it',
    );
    await closeView(tester, d);
  }, variant: onMac);

  for (final brightness in Brightness.values) {
    for (final width in [1700.0, 720.0]) {
      testWidgets('renders: the count of the whole chat, then a match '
          'loaded by a step (${brightness.name}, $width)', (tester) async {
        final (d, _, _) = await _window(
          tester,
          size: Size(width, 1000),
          brightness: brightness,
        );
        final c = _chat(d);
        c.find
          ..open()
          ..query = 'needle';
        await _settle(tester);
        final name = 'find-all-${brightness.name}-${width.toInt()}';
        await render(tester, find.byType(NushiApp), '$name-count');
        c.find.step(1);
        await _settle(tester);
        await _settle(tester);
        expect(_shows(tester, 'Turn 5 left a needle'), isTrue);
        await render(tester, find.byType(NushiApp), '$name-stepped');
        await closeView(tester, d);
      }, variant: onMac);
    }
  }
}

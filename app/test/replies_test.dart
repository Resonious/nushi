import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/replies.dart';

void main() {
  test('a message with replies, and back', () {
    const replies = [
      (quote: 'line one\nline two', text: 'why?', from: ''),
      (quote: 'just this', text: '', from: ''),
    ];
    final message = withReplies(replies, 'and the rest');
    expect(
      message,
      '<!-- reply 1 -->\n> line one\n> line two\n\nwhy?\n\n'
      '<!-- reply 2 -->\n> just this\n\n'
      '<!-- end of replies -->\n\nand the rest',
    );
    // The mark says where the replies end, so what follows a reply
    // without text is the message's own, to an agent as to Nushi.
    var (got, rest) = splitReplies(message);
    expect(got, replies);
    expect(rest, 'and the rest');
    // One sent before the mark was always there (0.42.0 and older): a
    // reply without text followed by text reads as that reply's text.
    (got, rest) = splitReplies('<!-- reply 1 -->\n> just this\n\nthe rest');
    expect(got, [(quote: 'just this', text: 'the rest', from: '')]);
    expect(rest, '');
    (got, rest) = splitReplies(withReplies(replies, ''));
    expect(got, replies);
    expect(rest, '');
    (got, rest) = splitReplies(withReplies(replies.sublist(0, 1), 'a\n\nb'));
    expect(got, replies.sublist(0, 1));
    expect(rest, 'a\n\nb');
    (got, rest) = splitReplies('> a plain quote');
    expect(got, isEmpty);
    expect(rest, '> a plain quote');
  });

  test('a reply with lines, and with a blank line, comes back whole', () {
    const lines = (
      quote: 'kept as a DateTime',
      text: 'Why?\nAnd why not a string?',
      from: '',
    );
    var message = withReplies([lines], 'the rest');
    expect(message, contains('\n\n<!-- end of replies -->\n\nthe rest'));
    // None when nothing follows the replies and none has a blank line.
    expect(withReplies([lines], ''), isNot(contains('end of replies')));
    var (got, rest) = splitReplies(message);
    expect(got, [lines]);
    expect(rest, 'the rest');

    const paragraphs = (
      quote: 'kept as a DateTime',
      text: 'Why?\n\nAnd why not?',
      from: '',
    );
    for (final text in ['the rest', '']) {
      message = withReplies([lines, paragraphs], text);
      expect(
        message,
        '<!-- reply 1 -->\n> kept as a DateTime\n\nWhy?\nAnd why not a string?'
        '\n\n<!-- reply 2 -->\n> kept as a DateTime\n\nWhy?\n\nAnd why not?'
        '\n\n<!-- end of replies -->${text.isEmpty ? '' : '\n\n$text'}',
      );
      (got, rest) = splitReplies(message);
      expect(got, [lines, paragraphs]);
      expect(rest, text);
    }
  });

  // Whose the quoted text is: one lead line per group (the coordinator's
  // case: Claude took the user's own review comments for a reviewer's).
  test("a group's lead line once before it, and back to its first reply", () {
    const mine = 'My review comments on your changes:';
    const theirs =
        'Review comments from @octo on PR a/b#1 (GitHub), my pull '
        'request:';
    const replies = [
      (quote: 'a.go, line 1', text: 'Rename it.', from: mine),
      (quote: 'a.go, line 2', text: 'Drop it.', from: mine),
      (quote: 'Overflow?', text: 'Address it.', from: theirs),
      (quote: 'selected text', text: 'why?', from: ''),
    ];
    final message = withReplies(replies, 'Thanks.');
    expect(
      message,
      '<!-- from -->\n$mine\n\n'
      '<!-- reply 1 -->\n> a.go, line 1\n\nRename it.\n\n'
      '<!-- reply 2 -->\n> a.go, line 2\n\nDrop it.\n\n'
      '<!-- from -->\n$theirs\n\n'
      '<!-- reply 3 -->\n> Overflow?\n\nAddress it.\n\n'
      '<!-- reply 4 -->\n> selected text\n\nwhy?\n\n'
      '<!-- end of replies -->\n\nThanks.',
    );
    final (got, rest) = splitReplies(message);
    expect(rest, 'Thanks.');
    expect([for (final r in got) r.from], [mine, '', theirs, '']);
    expect(
      [for (final r in got) r.text],
      ['Rename it.', 'Drop it.', 'Address it.', 'why?'],
    );
    // Sent again as parsed, the leads are the same.
    expect(withReplies(got, 'Thanks.'), message);
  });

  test('a lead with a newline in it (a name from GitHub) stays one line, '
      'and the replies come back', () {
    const replies = [
      (
        quote: 'Check CI / lint\nfast: failure',
        text: 'Fix it.',
        from: 'Failed checks on PR a/b#1\n(GitHub):',
      ),
    ];
    final message = withReplies(replies, 'Thanks.');
    expect(
      message,
      startsWith('<!-- from -->\nFailed checks on PR a/b#1 (GitHub):\n\n'),
    );
    final (got, rest) = splitReplies(message);
    expect(rest, 'Thanks.');
    expect(got.single.from, 'Failed checks on PR a/b#1 (GitHub):');
    expect(got.single.quote, 'Check CI / lint\nfast: failure');
    expect(got.single.text, 'Fix it.');
  });

  // The agent answers "#1 … #2 …" by the number in each card's mark, which
  // the cards show from two up (ReplyNumber); the mark is the only
  // structure, so no words of Nushi's reach the agent.
  test('one, two and three cards: each mark numbered by its place', () {
    const a = (quote: 'main.go, line 3', text: 'Rename it.', from: '');
    const b = (quote: 'main.go, line 9', text: 'Drop it.', from: '');
    const c = (quote: 'kept as a DateTime', text: 'Why?', from: '');
    expect(
      withReplies([a], ''),
      '<!-- reply 1 -->\n> main.go, line 3\n\nRename it.',
    );
    expect(
      withReplies([a, b], ''),
      '<!-- reply 1 -->\n> main.go, line 3\n\nRename it.\n\n'
      '<!-- reply 2 -->\n> main.go, line 9\n\nDrop it.',
    );
    final three = withReplies([a, b, c], 'Thanks.');
    expect(
      three,
      '<!-- reply 1 -->\n> main.go, line 3\n\nRename it.\n\n'
      '<!-- reply 2 -->\n> main.go, line 9\n\nDrop it.\n\n'
      '<!-- reply 3 -->\n> kept as a DateTime\n\nWhy?\n\n'
      '<!-- end of replies -->\n\nThanks.',
    );
    // Write, read, write: the same text; the numbers aren't kept on a
    // card, its place gives them again.
    final (got, rest) = splitReplies(three);
    expect(got, [a, b, c]);
    expect(withReplies(got, rest), three);
    // A card taken out: the rest are numbered again from 1.
    final two = withReplies([b, c], '');
    expect(two, startsWith('<!-- reply 1 -->\n> main.go, line 9'));
    expect(two, contains('<!-- reply 2 -->\n> kept as'));
  });

  test('marks whose numbers are out of step still read by place', () {
    // Text written by hand, or an older message edited: each mark is a
    // card, whatever its number.
    const message =
        '<!-- reply 4 -->\n> one\n\nfirst\n\n'
        '<!-- reply 4 -->\n> two\n\nsecond\n\n'
        '<!-- end of replies -->\n\nrest';
    final (got, rest) = splitReplies(message);
    expect([for (final r in got) r.quote], ['one', 'two']);
    expect([for (final r in got) r.text], ['first', 'second']);
    expect(rest, 'rest');
    expect(withReplies(got, rest), contains('<!-- reply 2 -->\n> two'));
  });

  test("a card's own numbered lines stay its own", () {
    const listed = (
      quote: '1. parse the time\n2. sort by it\n10. done',
      text: '1. Why parse?\n2. Why not sort strings?',
      from: '',
    );
    const leading = (quote: '1.', text: '2. and this', from: '');
    final message = withReplies([listed, leading], '3. and the rest');
    expect(message, contains('> 1. parse the time\n> 2. sort by it'));
    final (got, rest) = splitReplies(message);
    expect(got, [listed, leading]);
    expect(rest, '3. and the rest');
    expect(withReplies(got, rest), message);
  });
}

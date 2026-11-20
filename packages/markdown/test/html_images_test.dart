import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_view/markdown_view.dart';

const _style = MarkdownStyle(
  body: TextStyle(fontSize: 13.5, height: 1.5),
  code: TextStyle(fontSize: 12.5),
  codeBackground: Colors.black12,
  codeRadius: 6,
  border: Colors.grey,
  muted: Colors.grey,
  link: Colors.blue,
  highlight: _plain,
);

TextSpan? _plain(String language, String code, TextStyle style) => null;

/// [text] shown with an image builder that records what it was asked
/// and draws a 400 square keyed by the image's path.
Future<List<(String, String?)>> _show(
  WidgetTester tester,
  String text, {
  bool streaming = false,
}) async {
  final asked = <(String, String?)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StreamingMarkdown(
            text,
            style: _style,
            streaming: streaming,
            imageBuilder: (uri, alt) {
              asked.add((uri.toString(), alt));
              return SizedBox(key: Key(uri.path), width: 400, height: 400);
            },
          ),
        ),
      ),
    ),
  );
  return asked;
}

void main() {
  testWidgets('an <img> in a line and in a heading is an image', (
    tester,
  ) async {
    final asked = await _show(
      tester,
      '# <img src="docs/logo.png" alt="Acme" width="32"> Acme\n\n'
      'Built with <IMG SRC=\'badge.svg\' alt="a badge &amp; more"/> today.',
    );
    expect(asked, [('docs/logo.png', 'Acme'), ('badge.svg', 'a badge & more')]);
    expect(find.textContaining('<img', findRichText: true), findsNothing);
    expect(find.textContaining('<IMG', findRichText: true), findsNothing);
    expect(find.textContaining('today.', findRichText: true), findsOne);
    // At most its width; the other as the builder drew it.
    expect(tester.getSize(find.byKey(const Key('docs/logo.png'))).width, 32);
    expect(tester.getSize(find.byKey(const Key('badge.svg'))).width, 400);
  });

  testWidgets("a README's centered logo: the image, without its wrapper's "
      'tags', (tester) async {
    final asked = await _show(
      tester,
      '<p align="center">\n'
      '  <img src="assets/logo.png" alt="Logo" width="120px" height="60">\n'
      '</p>\n\n'
      '<h1 align="center"><img src="mark.png"><br>Acme</h1>\n\n'
      'After.',
    );
    expect(asked, [('assets/logo.png', 'Logo'), ('mark.png', null)]);
    final logo = tester.getSize(find.byKey(const Key('assets/logo.png')));
    expect((logo.width, logo.height), (120, 60));
    expect(find.textContaining('<p', findRichText: true), findsNothing);
    expect(find.textContaining('</h1>', findRichText: true), findsNothing);
    expect(find.textContaining('Acme', findRichText: true), findsOne);
    expect(find.textContaining('After.', findRichText: true), findsOne);
  });

  testWidgets('other HTML, code and an <img> without a src stay as text', (
    tester,
  ) async {
    final asked = await _show(
      tester,
      '<details>\n<summary>More</summary>\n</details>\n\n'
      'Write `<img src="x.png">` for one; <img alt="none"> has no src.\n\n'
      '```html\n<img src="y.png">\n```\n',
    );
    expect(asked, isEmpty);
    expect(find.textContaining('<details>', findRichText: true), findsOne);
    expect(
      find.textContaining('<img src="x.png">', findRichText: true),
      findsOne,
    );
    expect(
      find.textContaining('<img alt="none">', findRichText: true),
      findsOne,
    );
  });

  testWidgets('while it streams, an <img> is an image too', (tester) async {
    final asked = await _show(
      tester,
      'Here: <img src="a.png" alt="A"> and on',
      streaming: true,
    );
    expect(asked, [('a.png', 'A')]);
  });

  testWidgets('without an image builder, its alt text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StreamingMarkdown(
            'A <img src="a.png" alt="logo"> here.',
            style: _style,
            streaming: false,
          ),
        ),
      ),
    );
    expect(find.text('[image: logo]'), findsOne);
  });
}

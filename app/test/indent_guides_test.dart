import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/indent_guides.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/source_editor.dart';
import 'package:nushi/source_spans.dart';
import 'package:nushi/source_view.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/whitespace_marks.dart';

import 'fake_daemon.dart';
import 'file_edit_helpers.dart';
import 'harness.dart';

// Indent guides (the Files pane's ⋯, Claude desktop's): a faint line down
// each indent level, in the source and the editor.

/// Python, indented with four spaces, a blank line inside its block.
const _python =
    'def brew(tea):\n'
    '    if tea:\n'
    '        pour(tea)\n'
    '\n'
    '        stir(tea)\n'
    '    return tea\n';

/// The same, indented with two spaces, as Dart, JS and YAML are.
final String _python2 = _python.replaceAll('    ', '  ');

/// The x of each guide [of] paints.
List<double> _guides(WidgetTester tester, Finder of) {
  final xs = <double>[];
  expect(
    tester.renderObject(of),
    paints..everything((method, args) {
      if (method == #drawLine) xs.add((args[0] as Offset).dx);
      return true;
    }),
  );
  return xs;
}

Finder _line(String text) => find.ancestor(
  of: find.textContaining(text, findRichText: true).first,
  matching: find.byType(IndentGuides),
);

void main() {
  setUpAll(loadFonts);

  group('indents', () {
    test('leading columns in steps of the tab size, a tab to its stop', () {
      expect(indents(['    a', '\ta', '  \ta', '        a', 'a'], 4).levels, [
        1,
        1,
        1,
        2,
        0,
      ]);
      expect(indents(['\ta', '\t\ta', '  a'], 2).levels, [1, 2, 1]);
      expect(indents(['\t\ta'], 8).levels, [2]);
    });

    test('a file indenting with spaces steps what it indents by, whatever '
        'the tab size: 2-space code gets a guide per level', () {
      final two = ['a', '  b', '    c', '      d', '  e', 'f'];
      for (final size in tabSizes) {
        expect(indents(two, size).levels, [0, 1, 2, 3, 1, 0]);
        expect(indents(two, size).unit, 2);
      }
      final four = ['a', '    b', '        c', '    d'];
      for (final size in tabSizes) {
        expect(indents(four, size).levels, [0, 1, 2, 1]);
        expect(indents(four, size).unit, 4);
      }
      // Its most common step wins over an odd one (an aligned argument).
      expect(indents(['a', '  b', '    c', '       d', '  e'], 4).unit, 2);
      // Nothing indented: the tab size.
      expect(indents(['a', 'b'], 8).unit, 8);
      // Tabs: a tab's size, with a stray space-indented line.
      final tabs = indents(['a', '\tb', '\t\tc', '  d'], 4);
      expect(tabs.levels, [0, 1, 2, 0]);
      expect(tabs.unit, 4);
    });

    test('a blank line takes the lesser of the lines around it; one at the '
        'end or the start, none', () {
      expect(indents(['a', '    b', '', '        c', '    d', ''], 4).levels, [
        0,
        1,
        1,
        2,
        1,
        0,
      ]);
      expect(indents(['', '  ', '    a'], 4).levels, [0, 0, 1]);
    });

    test('a blank run past the look has none, and one pass each way does '
        'it', () {
      final lines = [
        '        a',
        for (var i = 0; i < 500; i++) '',
        '        b',
      ];
      final levels = indents(lines, 4).levels;
      // The line with text after it is 500 on: past the look, so none.
      expect(levels[1], 0);
      expect(levels[250], 0, reason: 'past 200 lines each way');
      expect(levels[500], 0);
      expect(
        indents(['    a', ...List.filled(199, ''), '    b'], 4).levels[1],
        1,
      );
      // Large and linear: 50,000 lines of long blank runs (150 each,
      // within the look), each line read three times however long its
      // run, where a look per blank line would read it hundreds of times.
      final big = [
        for (var i = 0; i < 50000; i++)
          if (i % 151 == 0) '    x' else '',
      ];
      indentLinesRead = 0;
      final read = indents(big, 4).levels;
      expect(read, hasLength(50000));
      expect(read[75], 1, reason: 'a blank in the middle of a run');
      expect(indentLinesRead, lessThanOrEqualTo(3 * big.length));
    });

    test('the guides sit at each level’s first column', () {
      expect(guidesAt(3, 28).toList(), [0, 28, 56]);
      expect(guidesAt(0, 28), isEmpty);
    });
  });

  for (final wrap in [true, false]) {
    testWidgets('the source view draws a line per level, the blank line '
        'too, a tab’s columns apart; none with them off, wrap $wrap', (
      tester,
    ) async {
      viewport(tester, const Size(900, 600));
      Future<void> show({required bool guides, int size = 4}) async {
        await tester.pumpWidget(
          themed(
            SourceView(
              _python,
              path: 'brew.py',
              wrap: wrap,
              tabSize: size,
              guides: guides,
            ),
          ),
        );
        await tester.pump();
      }

      await show(guides: true);
      final context = tester.element(find.byType(SourceView));
      final column = columnWidth(
        DefaultTextStyle.of(context).style
            .merge(NushiTheme.of(context).code(Colors.black, size: 12)),
        TextScaler.noScaling,
      );
      final pour = _guides(tester, _line('pour'));
      expect(pour, hasLength(2));
      expect(pour[1] - pour[0], closeTo(4 * column, 1));
      expect(_guides(tester, _line('if tea')), hasLength(1));
      expect(_guides(tester, _line('def brew')), isEmpty);
      // The blank line between pour and stir keeps both.
      expect(
        tester
            .widgetList<IndentGuides>(find.byType(IndentGuides))
            .map((g) => g.level),
        containsAllInOrder([0, 1, 2, 2, 2, 1]),
      );
      final line = tester.getRect(_line('pour'));
      expect(
        tester.getSize(find.byType(IndentGuides).at(2)).height,
        line.height,
      );
      expect(
        tester.widget<IndentGuides>(_line('pour')).color,
        whitespaceColor(NushiTheme.of(context).t),
      );

      // At a tab size of 2 the file still steps its own 4.
      await show(guides: true, size: 2);
      expect(_guides(tester, _line('pour')), hasLength(2));

      await show(guides: false);
      expect(_guides(tester, _line('pour')), isEmpty);

      // A 2-space file at the tab size of 4: a guide per level, 2 apart.
      await tester.pumpWidget(
        themed(SourceView(_python2, path: 'brew.py', wrap: wrap, guides: true)),
      );
      await tester.pump();
      final two = _guides(tester, _line('pour'));
      expect(two, hasLength(2));
      expect(two[1] - two[0], closeTo(2 * column, 1));
      expect(_guides(tester, _line('if tea')), hasLength(1));
    });
  }

  testWidgets('the editor draws them where re_editor lays its lines out; '
      'the text and the saved bytes are as they were', (tester) async {
    final (d, fake) = await openEditor(
      tester,
      {'brew.py': utf8.encode(_python)},
      open: const ['brew.py'],
    );
    expect(find.byType(IndentGuideOverlay), findsOneWidget);
    final lines = <(Offset, Offset)>[];
    expect(
      tester.renderObject(
        find.descendant(
          of: find.byType(IndentGuideOverlay),
          matching: find.byType(CustomPaint),
        ),
      ),
      paints..everything((method, args) {
        if (method == #drawLine) {
          lines.add((args[0] as Offset, args[1] as Offset));
        }
        return true;
      }),
    );
    // def 0, if 1, pour 2, the blank 2, stir 2, return 1.
    expect(lines, hasLength(8));
    final xs = {for (final (a, _) in lines) a.dx}.toList()..sort();
    expect(xs, hasLength(2));
    final step =
        4 *
        columnWidth(
          NushiTheme.of(tester.element(find.byType(SourceEditor)))
              .code(Colors.black, size: 12),
          TextScaler.noScaling,
        );
    expect(xs[1] - xs[0], closeTo(step, 1));
    final e = editOf(d, 'brew.py');
    expect(e.controller.text, _python);
    indentGuides.value = false;
    await tester.pump();
    expect(find.byType(IndentGuideOverlay), findsNothing);
    indentGuides.value = true;
    await tester.pump();
    expect(find.byType(IndentGuideOverlay), findsOneWidget);
    await typeIn(tester, e, 'x');
    await e.save();
    await tester.pump();
    expect(utf8.decode(fake.writes.last.data), contains('def brew'));
    expect(utf8.decode(fake.writes.last.data), isNot(contains('│')));
    await endEditor(tester, d);
  }, variant: onMac);

  testWidgets('a wrapped line’s guides stop at its first row: its next '
      'rows start under them, in the source and the editor', (tester) async {
    final long = '${'word ' * 80}end';
    final text = 'def brew(tea):\n    if tea:\n        $long\n';
    // The source.
    viewport(tester, const Size(400, 600));
    await tester.pumpWidget(
      themed(SourceView(text, path: 'brew.py', guides: true)),
    );
    await tester.pump();
    final line = _line('end');
    final box = tester.getSize(line);
    final drawn = <double>[];
    expect(
      tester.renderObject(line),
      paints..everything((method, args) {
        if (method == #drawLine) {
          drawn.add((args[1] as Offset).dy - (args[0] as Offset).dy);
        }
        return true;
      }),
    );
    expect(drawn, hasLength(2));
    final row = tester.getSize(_line('if tea')).height;
    for (final h in drawn) {
      expect(h, lessThan(box.height / 2), reason: 'wrapped, ${box.height}');
      expect(h, closeTo(row, 2));
    }
    // The editor.
    final (d, _) = await openEditor(
      tester,
      {'brew.py': utf8.encode(text)},
      open: const ['brew.py'],
      width: 900,
    );
    final lengths = <double>[];
    expect(
      tester.renderObject(
        find.descendant(
          of: find.byType(IndentGuideOverlay),
          matching: find.byType(CustomPaint),
        ),
      ),
      paints..everything((method, args) {
        if (method == #drawLine) {
          lengths.add((args[1] as Offset).dy - (args[0] as Offset).dy);
        }
        return true;
      }),
    );
    // if 1, the long line 2: each one row high.
    expect(lengths, hasLength(3));
    expect(lengths.toSet(), hasLength(1));
    await endEditor(tester, d);
  }, variant: onMac);

  testWidgets('the editor steps a 2-space file’s own 2 at a tab size of 4', (
    tester,
  ) async {
    final (d, _) = await openEditor(
      tester,
      {'brew.py': utf8.encode(_python2)},
      open: const ['brew.py'],
    );
    final xs = <double>{};
    expect(
      tester.renderObject(
        find.descendant(
          of: find.byType(IndentGuideOverlay),
          matching: find.byType(CustomPaint),
        ),
      ),
      paints..everything((method, args) {
        if (method == #drawLine) xs.add((args[0] as Offset).dx);
        return true;
      }),
    );
    final sorted = xs.toList()..sort();
    expect(sorted, hasLength(2));
    final column = columnWidth(
      NushiTheme.of(tester.element(find.byType(SourceEditor)))
          .code(Colors.black, size: 12),
      TextScaler.noScaling,
    );
    expect(sorted[1] - sorted[0], closeTo(2 * column, 1));
    await endEditor(tester, d);
  }, variant: onMac);

  for (final (name, tokens) in [
    ('dark', Tokens.dark),
    ('light', Tokens.light),
  ]) {
    testWidgets('guides in a 4-space and a 2-space source, $name', (
      tester,
    ) async {
      viewport(tester, const Size(520, 140));
      await tester.pumpWidget(
        themed(
          tokens: tokens,
          RepaintBoundary(
            key: const ValueKey('guides'),
            child: ColoredBox(
              color: tokens.base,
              child: Row(
                children: [
                  for (final text in [_python, _python2])
                    Expanded(
                      child: SourceView(
                        text,
                        path: 'brew.txt',
                        wrap: false,
                        guides: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byKey(const ValueKey('guides')),
        matchesGoldenFile('goldens/indent_guides_$name.png'),
      );
    }, variant: onMac);
  }
}

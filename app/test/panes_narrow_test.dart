import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/controls.dart';
import 'package:nushi/file_view.dart';
import 'package:nushi/files_bar.dart';
import 'package:nushi/files_pane.dart';
import 'package:nushi/files_split.dart' show filesTreeFolds;
import 'package:nushi/files_tree.dart';
import 'package:nushi/folder_tree.dart';
import 'package:nushi/settings.dart' show filesTree;

import 'browser_fixture.dart' show browserFakes;
import 'harness.dart';
import 'panes_app.dart';

// Panes in a narrow window (ADR 0123): under their summed least they lie
// over the transcript and narrow to fit, each down to the least its rows
// hold before the others give, so no row overflows in a window from 600:
// theirs, or the transcript's beside them at its own least. One pane
// alone holds down to a 400 window, the sidebar shown or not (it tucks
// itself away there). Any overflow fails a test: none is let through.

/// Each laid-out row whose children overflow it (a [RenderFlex] says so
/// in its short description), by where it was made.
List<String> _overflows(WidgetTester tester) => [
  for (final e in find.byWidgetPredicate((w) => w is Flex).evaluate())
    if (e.renderObject case final RenderFlex r
        when r.hasSize && r.toStringShort().contains('OVERFLOWING'))
      '${r.size.width.toStringAsFixed(1)} ${_where(e)}',
];

/// The file and line that made [e].
String _where(Element e) {
  final chain = e.debugGetCreatorChain(9);
  return RegExp(r'lib/([a-z_]+\.dart:\d+)').firstMatch(chain)?.group(1) ??
      chain;
}

PanesOpen _with({
  bool subagent = false,
  bool browser = false,
  int previews = 1,
}) => (
  side: true,
  files: true,
  subagent: subagent,
  command: false,
  previews: previews,
  browser: browser ? 1 : 0,
);

/// The width the Files pane gives its tree (its edge's box), 0 when it's
/// squeezed out and so not there.
double _treeRoom(WidgetTester tester) {
  final tree = find.ancestor(
    of: find.byType(FilesTree),
    matching: find.byKey(const ValueKey('tree')),
  );
  return tree.evaluate().isEmpty ? 0 : tester.getSize(tree).width;
}

/// Each laid-out box in the Files pane that runs past its right edge, by
/// what made it.
List<String> _pastFiles(WidgetTester tester) {
  final pane = tester.getRect(find.byType(FilesPane));
  return [
    for (final e
        in find
            .descendant(
              of: find.byType(FilesPane),
              matching: find.byWidgetPredicate((_) => true),
            )
            .evaluate())
      if (e.renderObject case final RenderBox r when r.hasSize)
        if (r.localToGlobal(Offset(r.size.width, 0)).dx case final right
            when right > pane.right + 0.5)
          '${e.widget.runtimeType} to $right',
  ];
}

void main() {
  for (final width in [400.0, 480.0, 520.0, 560.0]) {
    for (final sidebar in [true, false]) {
      testWidgets('Files alone in a ${width.round()} window, sidebar '
          "${sidebar ? 'shown' : 'hidden'}: the tree there at a width its "
          'rows hold or not at all, nothing past the pane', (tester) async {
        final (d, _) = await panesApp(
          tester,
          width: width,
          sidebar: sidebar,
          open: (
            side: false,
            files: true,
            subagent: false,
            command: false,
            previews: 0,
            browser: 0,
          ),
        );
        final tree = _treeRoom(tester);
        // In 520 to 580 the tree was a sliver of 1 to 70, its field and
        // rows running past it.
        expect(tree == 0 || tree >= filesTreeFolds, isTrue, reason: '$tree');
        expect(_pastFiles(tester), isEmpty);
        expect(_overflows(tester), isEmpty);
        expectTextInside(tester, width);
        await closeView(tester, d);
      }, variant: onMac);
    }
  }

  for (final (name, open) in [
    ('side + Files + browser', _with(browser: true)),
    ('side + Files + subagent', _with(subagent: true)),
  ]) {
    for (final sidebar in [true, false]) {
      testWidgets('$name, sidebar ${sidebar ? 'shown' : 'hidden'}: '
          'nothing overflows from 600 to 900', (tester) async {
        browserFakes();
        final found = <String>[];
        for (var w = 900.0; w >= 600; w -= 10) {
          final (d, _) = await panesApp(
            tester,
            width: w,
            sidebar: sidebar,
            open: open,
          );
          found.addAll([for (final o in _overflows(tester)) '$w: $o']);
          await closeView(tester, d);
        }
        expect(found, isEmpty);
      }, variant: onMac);
    }
  }

  for (final sidebar in [true, false]) {
    testWidgets('side chat, Files and the browser in a 720 window, sidebar '
        "${sidebar ? 'shown' : 'hidden'}: Files' viewer has all of it, the "
        'tree slid away, its choice kept', (tester) async {
      browserFakes();
      final (d, _) = await panesApp(
        tester,
        width: 720,
        sidebar: sidebar,
        open: _with(browser: true),
      );
      final files = tester.getSize(find.byType(FilesPane)).width;
      // Narrowed alike, its viewer had 83 here and its tree 57, the file's
      // name breaking a letter or two a line.
      expect(files, lessThan(300));
      expect(tester.getSize(find.byType(FileView)).width, closeTo(files, 0.01));
      expect(_treeRoom(tester), 0);
      expect(filesTree.value, isTrue);
      expect(_overflows(tester), isEmpty);
      await closeView(tester, d);
    }, variant: onMac);
  }

  testWidgets("squeezed between the viewer's least and both's, the tree "
      'gives on; with no file the blank names ⌘P once it has gone', (
    tester,
  ) async {
    browserFakes();
    // The three need 1100; a chat of 1009, 1020 past the title buttons,
    // narrows Files, the widest, to 433: its viewer at its least, its
    // tree over its fold.
    final (d, _) = await panesApp(
      tester,
      width: 1225,
      open: _with(browser: true),
    );
    final files = tester.getSize(find.byType(FilesPane)).width;
    expect(files, closeTo(433.3, 0.1));
    expect(tester.getSize(find.byType(FileView)).width, closeTo(300, 0.01));
    expect(_treeRoom(tester), closeTo(files - 300, 0.01));
    expect(_overflows(tester), isEmpty);
    await closeView(tester, d);

    final (e, _) = await panesApp(
      tester,
      width: 720,
      open: _with(browser: true, previews: 0),
    );
    expect(_treeRoom(tester), 0);
    expect(find.textContaining('Go to a file with ⌘P'), findsOneWidget);
    expect(_overflows(tester), isEmpty);
    await closeView(tester, e);
  }, variant: onMac);

  testWidgets('squeezed out, the tree has no lit button: it says Show, '
      "it and Collapse can't be had, and the choice is kept", (tester) async {
    browserFakes();
    final (d, _) = await panesApp(
      tester,
      width: 720,
      open: _with(browser: true),
    );
    // A folder open, so only the squeeze keeps Collapse from it.
    folderTreeOf(d.chats['c']!).setOpen('auth', open: true);
    await tester.pumpAndSettle();
    expect(_treeRoom(tester), 0);
    Finder inBar(Finder f) => find.descendant(
      of: find.descendant(
        of: find.byType(FilesPane),
        matching: find.byType(FilesBar),
      ),
      matching: f,
    );
    IconTap button(LineIcon icon) => tester.widget<IconTap>(
      inBar(find.byWidgetPredicate((w) => w is IconTap && w.line == icon)),
    );
    final tree = button(LineIcon.fileTree);
    expect(tree.lit, isFalse);
    expect(tree.tooltip, withKey('Show file tree', '⇧⌘Y'));
    expect(tree.onTap, isNull);
    expect(button(LineIcon.collapseAll).onTap, isNull);

    await tester.tap(inBar(find.byTooltip('More')));
    await tester.pumpAndSettle();
    MenuItemButton row(String label) => tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(row('Show file tree').onPressed, isNull);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Show file tree'),
          matching: find.byType(MenuItemButton),
        ),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
    expect(row('Collapse all folders').onPressed, isNull);
    expect(filesTree.value, isTrue, reason: 'the choice is kept');
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await closeView(tester, d);
  }, variant: onMac);
}

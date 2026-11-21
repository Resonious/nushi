import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/app_actions.dart';
import 'package:nushi/chat_header.dart';
import 'package:nushi/file_view.dart';
import 'package:nushi/files_bar.dart';
import 'package:nushi/files_pane.dart';
import 'package:nushi/files_top_row.dart';
import 'package:nushi/files_tree.dart';
import 'package:nushi/main.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/preview_path.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/theme/theme.dart';

import 'fake_daemon.dart' show loadFonts;
import 'harness.dart';
import 'right_panes_fixture.dart';

// The Files pane's File tree position (ADR 0123), Claude desktop's:
// Automatic (the right, away from the transcript), Left or Right.

const PanesOpen _files = (
  side: false,
  files: true,
  subagent: false,
  command: false,
  previews: 0,
  browser: 0,
);

Finder get _pane => find.byType(FilesPane);
Finder get _tree => find.byType(FilesTree);
Finder get _more => find.descendant(
  of: find.byType(FilesBar),
  matching: find.byTooltip('More'),
);

Finder _row(String label) => find.ancestor(
  of: find.text(label, findRichText: true),
  matching: find.byWidgetPredicate(
    (w) => w is MenuItemButton || w is SubmenuButton,
  ),
);

/// The View menu's File Tree Position submenu.
PlatformMenu _viewPosition(WidgetTester tester) {
  final view = tester
      .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
      .menus
      .whereType<PlatformMenu>()
      .firstWhere((m) => m.label == 'View');
  return view.menus
      .expand((m) => m is PlatformMenuItemGroup ? m.members : [m])
      .whereType<PlatformMenu>()
      .firstWhere((m) => m.label == 'File Tree Position');
}

/// Picks [side] in the ⋯'s File tree position.
Future<void> _pick(WidgetTester tester, String side) async {
  await tester.tap(_more);
  await tester.pumpAndSettle();
  await tester.tap(find.text('File tree position'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(side));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);

  testWidgets('Automatic and Right put the tree at the pane’s right edge, '
      'Left at its left; the pane, the tree’s width and the second row’s '
      'buttons stay put, and the path keeps over the viewer', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: 1700,
      details: false,
      open: (
        side: false,
        files: true,
        subagent: false,
        command: false,
        previews: 1,
        browser: 0,
      ),
    );
    expect(filesTreeSide.value, TreeSide.automatic);
    final pane = tester.getRect(_pane);
    final tree = tester.getRect(_tree);
    final view = tester.getRect(find.byType(FileView));
    final more = tester.getRect(_more);
    expect(tree.right, pane.right);
    expect(view.right, tree.left);
    expect(view.left, pane.left);
    expect(tree.width, 260);

    await _pick(tester, 'Left');
    expect(filesTreeSide.value, TreeSide.left);
    expect(readSaved()['filesTreeSide'], 'left');
    expect(tester.getRect(_pane), pane);
    expect(
      tester.getRect(_tree),
      Rect.fromLTWH(pane.left, tree.top, 260, tree.height),
    );
    expect(tester.getRect(find.byType(FileView)).left, pane.left + 260);
    expect(tester.getRect(find.byType(FileView)).right, pane.right);
    expect(tester.getRect(_more), more);
    expect(
      tester.getRect(find.byType(PathLine)).left,
      greaterThanOrEqualTo(pane.left + 260),
    );
    await render(tester, find.byType(NushiApp), 'files_tree_left');

    // The ⋯ says where it is, its submenu checks it.
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _row('File tree position'),
        matching: find.text('Left'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('File tree position'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _row('Left'), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    await tester.tap(find.text('Right'));
    await tester.pumpAndSettle();
    expect(filesTreeSide.value, TreeSide.right);
    expect(tester.getRect(_tree), tree);
    expect(tester.getRect(find.byType(FileView)), view);
    await closeView(tester, d);
  }, variant: macAndLinux);

  for (final width in [200.0, 260.0, 480.0]) {
    testWidgets('opening, switching and closing files never move the tree, on '
        'either side, the tree ${width.toInt()} wide', (tester) async {
      for (final side in TreeSide.values) {
        final (d, _) = await panesApp(
          tester,
          width: 1700,
          details: false,
          open: _files,
          widths: {'filesTree': width},
        );
        filesTreeSide.value = side;
        await tester.pumpAndSettle();
        final c = d.chats['c']!;
        final tree = tester.getRect(_tree);
        expect(
          side == TreeSide.left ? tree.left : tree.right,
          side == TreeSide.left
              ? tester.getRect(_pane).left
              : tester.getRect(_pane).right,
        );
        c.openInFiles('PLAN.md');
        await tester.pumpAndSettle();
        expect(tester.getRect(_tree), tree, reason: '$side');
        c.openInFiles('NOTES.md');
        await tester.pumpAndSettle();
        expect(tester.getRect(_tree), tree, reason: '$side');
        c.openInFiles('PLAN.md');
        await tester.pumpAndSettle();
        expect(tester.getRect(_tree), tree, reason: '$side');
        c.files
          ..close(c.files.tabs.value.last)
          ..close(c.files.tabs.value.last);
        await tester.pumpAndSettle();
        expect(c.shownFile, isNull);
        expect(tester.getRect(_tree), tree, reason: '$side');
        expect(tree.width, width);
        await closeView(tester, d);
      }
    }, variant: onMac);
  }

  testWidgets('a file opening Files puts the tree where opening Files and '
      'then the file does', (tester) async {
    for (final side in TreeSide.values) {
      filesTreeSide.value = side;
      // Files first, then the file.
      var (d, _) = await panesApp(
        tester,
        width: 1700,
        details: false,
        open: _files,
      );
      d.chats['c']!.openInFiles('PLAN.md');
      await tester.pumpAndSettle();
      final tree = tester.getRect(_tree);
      await closeView(tester, d);
      // The file alone, Files closed.
      (d, _) = await panesApp(tester, width: 1700, details: false);
      expect(_tree, findsNothing);
      d.chats['c']!.openInFiles('PLAN.md');
      await tester.pumpAndSettle();
      expect(tester.getRect(_tree), tree, reason: '$side');
      await closeView(tester, d);
    }
  }, variant: onMac);

  testWidgets('the tree keeps its search and the viewer its file as it '
      'changes sides; its edge drags from the viewer’s side', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: 1700,
      details: false,
      open: _files,
    );
    d.chats['c']!.openInFiles('PLAN.md');
    await tester.pumpAndSettle();
    final file = tester.state(find.byType(FileView));
    await tester.enterText(
      find.descendant(of: _tree, matching: find.byType(TextField)),
      'read',
    );
    await tester.pumpAndSettle();
    final state = tester.state(_tree);
    filesTreeSide.value = TreeSide.left;
    await tester.pumpAndSettle();
    expect(tester.state(_tree), same(state));
    expect(tester.state(find.byType(FileView)), same(file));
    expect(find.text('read'), findsOneWidget);

    // Its edge is at its right now: dragged right, it widens.
    final tree = tester.getRect(_tree);
    final drag = await tester.startGesture(
      Offset(tree.right - Resizable.edgeWidth / 2, tree.center.dy),
    );
    // The first move wins the pointer for the edge.
    await drag.moveBy(const Offset(20, 0));
    await tester.pump();
    final from = tester.getRect(_tree).width;
    expect(from, greaterThanOrEqualTo(tree.width));
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(tester.getRect(_tree).width, from + 40);
    // The path follows it as it's dragged, over the viewer.
    expect(
      tester.getRect(find.byType(PathLine)).left,
      greaterThanOrEqualTo(tree.left + from + 40),
    );
    await drag.up();
    await tester.pumpAndSettle();
    expect(paneWidths.value['filesTree'], from + 40);
    expect(tester.getRect(_tree).left, tree.left);
    await closeView(tester, d);
  }, variant: onMac);

  testWidgets('View › File Tree Position and the palette set it too, the '
      'value now unavailable in each', (tester) async {
    final (d, _) = await panesApp(
      tester,
      width: 1700,
      details: false,
      open: _files,
    );
    final context = tester.element(find.byType(ChatHeader));
    List<String> palette() => [
      for (final a in appActions(context, d))
        if (a.enabled &&
            {Act.treeAutomatic, Act.treeLeft, Act.treeRight}.contains(a.act))
          a.title,
    ];
    expect(palette(), [
      'Put the file tree on the left',
      'Put the file tree on the right',
    ]);
    final menu = _viewPosition(tester);
    expect(
      [for (final m in menu.menus) m.label],
      ['Automatic', 'Left', 'Right'],
    );
    expect(menu.menus.first.onSelected, isNull);
    menu.menus[1].onSelected!();
    await tester.pumpAndSettle();
    expect(filesTreeSide.value, TreeSide.left);
    expect(_viewPosition(tester).menus[1].onSelected, isNull);
    expect(palette(), [
      'Place the file tree automatically',
      'Put the file tree on the right',
    ]);
    runAct(context, d, Act.treeAutomatic);
    await tester.pumpAndSettle();
    expect(filesTreeSide.value, TreeSide.automatic);
    await closeView(tester, d);
  }, variant: onMac);

  for (final (name, tokens) in [
    ('dark', Tokens.dark),
    ('light', Tokens.light),
  ]) {
    testWidgets('the pane with its tree on the left, $name', (tester) async {
      final (d, _) = await panesApp(tester, width: 640, height: 400);
      final c = d.chats['c']!..openInFiles('PLAN.md');
      filesTreeSide.value = TreeSide.left;
      viewport(tester, const Size(640, 400));
      await tester.pumpWidget(
        themed(
          FilesPane(chat: c, daemon: d, onClose: () {}),
          tokens: tokens,
          banner: false,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(FilesPane),
        matchesGoldenFile('goldens/files_tree_left_$name.png'),
      );
      await closeView(tester, d);
    }, variant: onMac);
  }

  for (final side in [TreeSide.right, TreeSide.left]) {
    testWidgets('Tab goes through Files as it reads, the tree on the '
        '${side.name}: its search, then its rows, where the tree is', (
      tester,
    ) async {
      filesTreeSide.value = side;
      final (d, _) = await panesApp(
        tester,
        width: 1700,
        open: (
          side: false,
          files: true,
          subagent: false,
          command: false,
          previews: 1,
          browser: 0,
        ),
      );
      final parts = <(String, Finder)>[
        ('top', find.byType(FilesTopRow)),
        ('bar', find.byType(FilesBar)),
        ('viewer', find.byType(FileView)),
        ('tree', find.byType(FilesTree)),
      ];
      String? part(FocusNode n) {
        final ctx = n.context;
        if (ctx == null) return null;
        if (n.debugLabel == 'files filter') return 'search';
        for (final (name, f) in parts) {
          for (final e in f.evaluate()) {
            var hit = false;
            ctx.visitAncestorElements((a) => !(hit = a == e));
            if (hit || ctx == e) return name;
          }
        }
        return null;
      }

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final seen = <String>[];
      for (var i = 0; i < 80; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final n = FocusManager.instance.primaryFocus;
        final at = n == null ? null : part(n);
        if (at != null && !seen.contains(at)) seen.add(at);
      }
      expect(
        seen,
        side == TreeSide.left
            ? ['top', 'bar', 'search', 'tree', 'viewer']
            : ['top', 'bar', 'viewer', 'search', 'tree'],
      );
      await closeView(tester, d);
    }, variant: onMac);
  }
}

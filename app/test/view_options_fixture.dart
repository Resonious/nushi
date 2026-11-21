import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/app_actions.dart';
import 'package:nushi/chat_header.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/files_bar.dart';
import 'package:nushi/settings.dart';

import 'harness.dart';

// The Files pane's view options as each place words them (ADR 0123),
// written out here rather than read from the options' table, so a wrong
// label or a row wired to the wrong pref fails; and the places' rows.

/// An option that's on or off, as each place words it.
typedef ViewToggleWords = ({
  Pref<bool> pref,
  String key,
  Act act,
  String row,
  String viewOn,
  String viewOff,
  String paletteOn,
  String paletteOff,
});

final List<ViewToggleWords> toggleWords = [
  (
    pref: previewTabs,
    key: 'previewTabs',
    act: Act.previewTabs,
    row: 'Preview tabs',
    viewOn: 'Don’t Use Preview Tabs',
    viewOff: 'Use Preview Tabs',
    paletteOn: 'Don’t use preview tabs',
    paletteOff: 'Use preview tabs',
  ),
  (
    pref: wrapLines,
    key: 'wrap',
    act: Act.wrap,
    row: 'Word wrap',
    viewOn: 'Don’t Wrap Lines',
    viewOff: 'Wrap Lines',
    paletteOn: 'Don’t wrap lines in Files',
    paletteOff: 'Wrap lines in Files',
  ),
  (
    pref: indentGuides,
    key: 'indentGuides',
    act: Act.indentGuides,
    row: 'Indent guides',
    viewOn: 'Hide Indent Guides',
    viewOff: 'Show Indent Guides',
    paletteOn: 'Hide indent guides in Files',
    paletteOff: 'Show indent guides in Files',
  ),
  (
    pref: showWhitespace,
    key: 'whitespace',
    act: Act.whitespace,
    row: 'Show whitespace',
    viewOn: 'Hide Whitespace',
    viewOff: 'Show Whitespace',
    paletteOn: 'Hide whitespace in Files',
    paletteOff: 'Show whitespace in Files',
  ),
  (
    pref: scrollPastEnd,
    key: 'scrollPastEnd',
    act: Act.scrollPastEnd,
    row: 'Scroll past end',
    viewOn: 'Don’t Scroll Past End',
    viewOff: 'Scroll Past End',
    paletteOn: 'Don’t scroll past the end in Files',
    paletteOff: 'Scroll past the end in Files',
  ),
];

/// An option of a few values, as each place words it: its values' names
/// (the ⋯'s and View's), how each is saved, and its palette rows.
typedef ViewChoiceWords = ({
  Pref<Object?> pref,
  String key,
  String row,
  String view,
  List<(Object value, String name, Object saved, Act act, String palette)>
  values,
});

final List<ViewChoiceWords> choiceWords = [
  (
    pref: tabSize,
    key: 'tabSize',
    row: 'Tab size',
    view: 'Tab Size',
    values: [
      (2, '2', 2, Act.tabSize2, 'Tab size 2 in Files'),
      (4, '4', 4, Act.tabSize4, 'Tab size 4 in Files'),
      (8, '8', 8, Act.tabSize8, 'Tab size 8 in Files'),
    ],
  ),
  (
    pref: filesTreeSide,
    key: 'filesTreeSide',
    row: 'File tree position',
    view: 'File Tree Position',
    values: [
      (
        TreeSide.automatic,
        'Automatic',
        'automatic',
        Act.treeAutomatic,
        'Place the file tree automatically',
      ),
      (
        TreeSide.left,
        'Left',
        'left',
        Act.treeLeft,
        'Put the file tree on the left',
      ),
      (
        TreeSide.right,
        'Right',
        'right',
        Act.treeRight,
        'Put the file tree on the right',
      ),
    ],
  ),
];

/// The View menu's submenu called [label].
PlatformMenu viewSubmenu(WidgetTester tester, String label) =>
    viewItems(tester)
        .whereType<PlatformMenu>()
        .firstWhere((m) => m.label == label);

AppAction paletteRow(WidgetTester tester, Daemon d, Act act) => appActions(
  tester.element(find.byType(ChatHeader)),
  d,
).firstWhere((a) => a.act == act);

Finder get filesMore => find.descendant(
  of: find.byType(FilesBar),
  matching: find.byTooltip('More'),
);

/// The open menu's row of [label]: the nearest row around it (a
/// submenu's rows are inside its row).
Finder menuRow(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) => w is MenuItemButton || w is SubmenuButton,
      ),
    )
    .first;

bool menuChecked(String label) => find
    .descendant(of: menuRow(label), matching: find.byIcon(Icons.check))
    .evaluate()
    .isNotEmpty;

Future<void> openFilesMore(WidgetTester tester) async {
  await tester.tap(filesMore);
  await tester.pumpAndSettle();
}

Future<void> closeMenus(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 400));
  await tester.pumpAndSettle();
}

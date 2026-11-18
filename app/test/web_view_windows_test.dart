import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/toast.dart';
import 'package:nushi/web_view_windows.dart';

import 'harness.dart';

/// Where the runner was told to put the web view, and whether shown, in
/// order.
typedef _Bounds = List<(Rect, bool)>;

/// A web view whose runner is faked, its `bounds` calls kept in [into].
WebView2 _web(WidgetTester tester, _Bounds into) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('nushi/webview'),
    (call) async {
      if (call.method == 'bounds') {
        final a = (call.arguments as Map).cast<String, Object?>();
        into.add((
          Rect.fromLTWH(
            (a['x']! as int).toDouble(),
            (a['y']! as int).toDouble(),
            (a['width']! as int).toDouble(),
            (a['height']! as int).toDouble(),
          ),
          a['visible']! as bool,
        ));
      }
      return null;
    },
  );
  final web = WebView2(folder: 'unused', background: Colors.black);
  addTearDown(web.close);
  return web;
}

/// A menu button at [left] whose menu opens below it.
Widget _menu(String label, double left) => Positioned(
  left: left,
  top: 0,
  child: MenuAnchor(
    menuChildren: [
      MenuItemButton(onPressed: () {}, child: const Text('One item')),
    ],
    builder: (context, menu, _) =>
        TextButton(onPressed: menu.open, child: Text(label)),
  ),
);

/// The page: the menus' strip on the left, the web view from x 300 on.
Widget _page(WebView2 web) => themed(
  Stack(
    children: [
      Positioned(left: 300, top: 0, right: 0, bottom: 0, child: web.view()),
      _menu('Beside', 0),
      _menu('Over', 260),
    ],
  ),
);

void main() {
  testWidgets('it shows over its widget, and hides while a dialog is up', (
    tester,
  ) async {
    viewport(tester, const Size(800, 600));
    final bounds = <(Rect, bool)>[];
    await tester.pumpWidget(_page(_web(tester, bounds)));
    await tester.pump();
    expect(bounds.last, (const Rect.fromLTWH(300, 0, 500, 600), true));

    final context = tester.element(find.text('Beside'));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const Dialog(child: Text('A dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(bounds.last.$2, isFalse);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(bounds.last, (const Rect.fromLTWH(300, 0, 500, 600), true));
  });

  testWidgets('a menu over it hides it; a menu beside it leaves it', (
    tester,
  ) async {
    viewport(tester, const Size(800, 600));
    final bounds = <(Rect, bool)>[];
    await tester.pumpWidget(_page(_web(tester, bounds)));
    await tester.pump();

    await tester.tap(find.text('Beside'));
    await tester.pumpAndSettle();
    expect(find.text('One item'), findsOneWidget);
    expect(bounds.last.$2, isTrue, reason: 'the menu ends before x 300');
    await tester.tapAt(const Offset(150, 500)); // outside: it closes
    await tester.pumpAndSettle();

    await tester.tap(find.text('Over'));
    await tester.pumpAndSettle();
    expect(find.text('One item'), findsOneWidget);
    expect(bounds.last.$2, isFalse);
    await tester.tapAt(const Offset(150, 500));
    await tester.pumpAndSettle();
    expect(find.text('One item'), findsNothing);
    expect(bounds.last.$2, isTrue);
  });

  testWidgets('a toast over it hides it until it goes', (tester) async {
    viewport(tester, const Size(800, 600));
    final bounds = <(Rect, bool)>[];
    await tester.pumpWidget(_page(_web(tester, bounds)));
    await tester.pump();
    expect(bounds.last.$2, isTrue);

    showToast(
      Toasts.maybeOf(tester.element(find.text('Beside'))),
      'Saved',
      duration: const Duration(seconds: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved'), findsOneWidget);
    expect(bounds.last.$2, isFalse);
    await tester.pump(const Duration(seconds: 1)); // its time is up
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
    expect(bounds.last.$2, isTrue);
  });
}

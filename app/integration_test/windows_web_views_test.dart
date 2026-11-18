import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nushi/mermaid_windows.dart';
import 'package:nushi/native.dart';
import 'package:nushi/native_windows.dart';
import 'package:nushi/web_page_windows.dart';
import 'package:nushi/web_view_windows.dart';

// The Windows runner's web views (windows/runner/web_views.cpp, ADR 0134)
// against the real WebView2, through the Dart that uses them:
// `flutter test integration_test/windows_web_views_test.dart -d windows`
// with NUSHI_DATA naming a throwaway folder (the web views keep their data
// beside it, in `<folder>.WebView2`; without it every test skips rather
// than write beside the user's).
// The diagrams need `make mermaid`'s mermaid.min.js.

final Object _skip = !Platform.isWindows
    ? 'Windows only'
    : Platform.environment['NUSHI_DATA'] == null
    ? 'needs NUSHI_DATA, a throwaway data folder'
    : false;

/// Waits on the real clock, 20 s at most, until [done] answers non-null.
Future<T> _until<T>(String what, FutureOr<T?> Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    if (await done() case final T found) return found;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('never: $what');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  native = windowsNative();

  testWidgets(
    "a page shows at its widget's place, reads its root, and stays put "
    'when a script leaves',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('nushi-page-').path;
      addTearDown(() => Directory(root).deleteSync(recursive: true));
      File('$root\\inside.txt').writeAsStringSync('from the root');
      final page = '$root\\docs\\page one.html';
      File(page)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '<!doctype html><title>ok</title><p>A page</p>'
          // It tries to leave on its own, with no click.
          " <script>setTimeout(() => location.href = 'https://example.com/', "
          '8000)</script>',
        );
      final host = WindowsPage();
      addTearDown(host.dispose);
      final left = <String>[];
      host.web.onLeave = left.add;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: Builder(builder: host.view),
            ),
          ),
        ),
      );
      expect(await host.web.ready, isTrue);
      await host.load(page, root);
      await tester.pump();
      await _until('the page', () async {
        final title = await host.web.script('document.title');
        return title == 'ok' ? true : null;
      });
      // Laid out at the widget's size, in CSS pixels.
      await _until('its size', () async {
        await tester.pump();
        final w = await host.web.script('window.innerWidth');
        return w == 400 ? true : null;
      });
      expect(
        await host.web.script(
          '(() => { const x = new XMLHttpRequest(); '
          "x.open('GET', '/inside.txt', false); x.send(); "
          'return x.responseText; })()',
        ),
        'from the root',
      );
      final at = await host.web.script('location.href');
      expect('$at', endsWith('/docs/page%20one.html'));
      // Past ExecuteScript's own user activation (5 s) and the page's leave.
      await Future<void>.delayed(const Duration(seconds: 10));
      expect(await host.web.script('location.href'), at);
      expect(left, isEmpty, reason: "the page's own script is no click");
    },
    skip: _skip != false,
  );

  testWidgets('a diagram comes out as a PNG; a broken one says why', (
    tester,
  ) async {
    final mermaid = File('${mermaidFolder()}\\mermaid.min.js');
    if (!mermaid.existsSync()) {
      markTestSkipped('needs make mermaid');
      return;
    }
    const diagrams = WindowsDiagrams();
    final drawn = await diagrams.draw(
      'flowchart LR\n  A[Start] --> B{Is it?}\n  B -->|Yes| C[OK]',
      dark: false,
      width: 600,
      background: const ui.Color(0xFFFFFFFF),
      foreground: const ui.Color(0xFF000000),
    );
    expect(drawn.error, '');
    expect(drawn.png!.sublist(1, 4), 'PNG'.codeUnits);
    expect(drawn.width, greaterThan(100));
    final codec = await ui.instantiateImageCodec(drawn.png!);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, greaterThanOrEqualTo(drawn.width.floor()));
    final broken = await diagrams.draw(
      'flowchart LR\n  A -->',
      dark: true,
      width: 600,
      background: const ui.Color(0xFF000000),
      foreground: const ui.Color(0xFFFFFFFF),
    );
    expect((broken.png, broken.retry), (null, false));
    expect(broken.error, isNotEmpty);
    // A chain taller than a canvas may be (32767 pixels): drawn smaller,
    // not blank.
    final tall = await diagrams.draw(
      [
        'flowchart TB',
        for (var i = 0; i < 450; i++) '  n$i --> n${i + 1}',
      ].join('\n'),
      dark: false,
      width: 600,
      background: const ui.Color(0xFFFFFFFF),
      foreground: const ui.Color(0xFF000000),
    );
    expect(tall.error, '');
    expect(tall.height, greaterThan(32767));
    final tallImage = (await (await ui.instantiateImageCodec(
      tall.png!,
    )).getNextFrame()).image;
    expect(tallImage.height, lessThanOrEqualTo(16384));
    expect(tallImage.height, greaterThan(1000));
  }, skip: _skip != false);
}

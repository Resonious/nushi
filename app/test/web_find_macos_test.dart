import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/transcript_find.dart';
import 'package:nushi/web_find_macos.dart';

// The Mac's page find (issue 63, ADR 0143) asks the Swift side's PageFind
// over `nushi/browser`: what it sends, and what it makes of the answer.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("sends the query, the theme's colours as CSS and the bar's cover; "
      'reads the count back', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nushi/browser'), (
          call,
        ) async {
          calls.add(call);
          return switch (call.method) {
            'find' => {'count': 3, 'at': 1},
            'pageFocused' => true,
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('nushi/browser'), null),
    );
    final finder = WebKitFinder(() => 7);
    final found = await finder.find(
      'teapot',
      at: 1,
      colors: findColors(Tokens.light),
      cover: 56,
    );
    expect(found, (count: 3, at: 1));
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['id'], 7);
    expect(args['op'], 'find');
    expect(args['query'], 'teapot');
    expect(args['cover'], 56);
    for (final k in ['hit', 'now', 'edge']) {
      expect(args[k], matches(RegExp(r'^rgba\(\d+, \d+, \d+, [0-9.]+\)$')));
    }
    expect(args['edge'], endsWith('1.000)'));
    expect(await finder.focused(), isTrue);
    await finder.show(2, cover: 56);
    await finder.clear();
    await finder.focus();
    expect(
      [for (final c in calls) c.method],
      ['find', 'pageFocused', 'find', 'find', 'focusPage'],
    );
    expect((calls[2].arguments as Map)['op'], 'show');
    expect((calls[3].arguments as Map)['op'], 'clear');
    expect(calls[4].arguments, 7);
  });
}

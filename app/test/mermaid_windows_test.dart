import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/mermaid.dart';
import 'package:nushi/mermaid_windows.dart';

// Windows's diagrams against a faked runner (`nushi/webview`): its web
// views load the page at once, and their script answers or, while [hang]
// is set, never does, as a page busy with a diagram that's too heavy.

void main() {
  testWidgets('a diagram whose script never answers fails after 10 s, and '
      'the next is drawn in a new web view', (tester) async {
    const channel = MethodChannel('nushi/webview');
    final made = <int>[];
    final closed = <int>[];
    var hang = true;
    final png = base64Encode([1, 2, 3]);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      final a = (call.arguments as Map).cast<String, Object?>();
      final id = a['id']! as int;
      switch (call.method) {
        case 'make':
          made.add(id);
        case 'close':
          closed.add(id);
        case 'load':
          // The runner says the page finished, as it does once it loads.
          unawaited(
            Future(
              () => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
                channel.name,
                channel.codec.encodeMethodCall(
                  MethodCall('finished', {
                    'id': id,
                    'url': a['url'],
                    'ok': true,
                  }),
                ),
                (_) {},
              ),
            ),
          );
        case 'script':
          if (hang) return await Completer<String>().future;
          final poll = '${a['js']}'.contains('__nushi?.[');
          return poll
              ? jsonEncode({'png': png, 'width': 3, 'height': 1})
              : '{}';
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    /// One diagram drawn, the clock moved on until it answers (30 s at most).
    Future<(DrawnDiagram?, Duration)> drawn() async {
      DrawnDiagram? got;
      unawaited(
        const WindowsDiagrams()
            .draw(
              'graph TD; A-->B',
              dark: false,
              width: 400,
              background: Colors.white,
              foreground: Colors.black,
            )
            .then((d) => got = d),
      );
      var waited = Duration.zero;
      const step = Duration(milliseconds: 100);
      while (got == null && waited < const Duration(seconds: 30)) {
        await tester.pump(step);
        waited += step;
      }
      return (got, waited);
    }

    final (slow, took) = await drawn();
    expect(slow?.error, 'The diagram took too long to draw');
    expect(slow?.retry, isTrue);
    expect(took, greaterThanOrEqualTo(diagramJobWait));
    expect(took, lessThan(diagramJobWait + const Duration(seconds: 1)));
    expect(made, hasLength(1));
    expect(closed, made, reason: 'the stuck web view is closed');

    hang = false;
    final (next, _) = await drawn();
    expect(next?.error, '');
    expect(next?.png, [1, 2, 3]);
    expect(made, hasLength(2), reason: 'a new web view for the next');
    expect(made.last, isNot(made.first));
    expect(closed, hasLength(1));
  });
}

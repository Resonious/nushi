import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/details_panel.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/panel_widgets.dart';

import 'fake_daemon.dart';
import 'harness.dart';

// A chat just opened: the details panel doesn't flash "Not reported yet"
// and "…" for a frame or two, its rows folding and growing again as the
// numbers come. It waits for the chat's snapshot and its folder's status,
// Waits.slow at most, its rows unseen meanwhile.

/// How much of each chat's rows shows, the last chat's first: the
/// opacities over its cards, multiplied.
List<double> _layers(WidgetTester tester) => [
  for (final e in find.byType(PanelWidgets).evaluate())
    () {
      var o = 1.0;
      e.visitAncestorElements((a) {
        if (a.widget case FadeTransition(:final opacity)) o *= opacity.value;
        if (a.widget case Opacity(:final opacity)) o *= opacity;
        return a.widget is! DetailsPanel;
      });
      return o;
    }(),
];

/// How much of the current chat's rows shows.
double _shown(WidgetTester tester) => _layers(tester).last;

void main() {
  testWidgets('the rows wait for the chat and its folder, then show', (
    tester,
  ) async {
    final fake = FakeDaemon([Chat(id: 'c', agent: 'claude', folder: '/x')])
      ..answer = (input) => switch (input) {
        GetFolderStatusRequest() => Future.delayed(
          const Duration(milliseconds: 40),
          GetFolderStatusResponse.new,
        ),
        _ => null,
      };
    final d = await fake.connect(tester);
    final chat = ChatState('c', '/x');
    await tester.pumpWidget(
      themed(DetailsPanel(chat: chat, daemon: d, onChanges: () {})),
    );
    expect(_shown(tester), 0);
    await tester.pump(const Duration(milliseconds: 60)); // the folder's
    expect(_shown(tester), 0, reason: 'the chat is still loading');
    chat
      ..loaded = true
      ..notifyListeners();
    await tester.pump();
    await tester.pump(Motion.quick ~/ 2);
    expect(_shown(tester), inExclusiveRange(0, 1), reason: 'fading in');
    await tester.pump(Motion.quick);
    expect(_shown(tester), 1);
    expect(find.text('Not a git repository'), findsWidgets);
    await closeView(tester, d);
  });

  testWidgets('what never comes doesn’t keep the rows away past Waits.slow', (
    tester,
  ) async {
    final fake = FakeDaemon([Chat(id: 'c', agent: 'claude', folder: '/x')]);
    final d = await fake.connect(tester);
    final chat = ChatState('c', '/x');
    await tester.pumpWidget(
      themed(DetailsPanel(chat: chat, daemon: d, onChanges: () {})),
    );
    await tester.pump(Waits.slow ~/ 2);
    expect(_shown(tester), 0);
    await tester.pump(Waits.slow);
    await tester.pump(Motion.quick);
    expect(_shown(tester), 1);
    await closeView(tester, d);
  });

  testWidgets(
    'another chat picked, the last one’s rows stay, dimmed past '
    'Waits.loading, until the new one’s are known, then fade through to them',
    (tester) async {
      final fake =
          FakeDaemon([
              Chat(id: 'a', agent: 'claude', folder: '/a'),
              Chat(id: 'b', agent: 'claude', folder: '/b'),
            ])
            ..answer = (input) => switch (input) {
              GetFolderStatusRequest(folder: '/b') => Future.delayed(
                const Duration(milliseconds: 40),
                () => GetFolderStatusResponse(git: true, branch: 'dark-mode'),
              ),
              _ => null,
            };
      final d = await fake.connect(tester);
      final a = ChatState('a', '/a')..loaded = true;
      final b = ChatState('b', '/b');
      final picked = ValueNotifier(a);
      await _picking(tester, d, picked);
      await tester.pumpAndSettle();
      expect(_layers(tester), [1]);
      picked.value = b;
      await tester.pump();
      // b's rows unseen, a's show still.
      expect(_layers(tester), [1, 0]);
      expect(find.text('Not a git repository'), findsOneWidget);
      await tester.pump(Waits.loading);
      await tester.pump(Motion.standard);
      expect(_layers(tester), [0.5, 0], reason: 'a’s dimmed: on their way out');
      await tester.pump(Waits.slow); // past the wait a blank pane would have
      expect(_layers(tester), [0.5, 0]);
      b
        ..loaded = true
        ..notifyListeners();
      await tester.pump();
      await tester.pump(); // the frame after: a's fade out
      await tester.pump(Motion.standard * 0.2);
      expect(_layers(tester)[0], inExclusiveRange(0, 0.5), reason: 'a’s go');
      expect(_layers(tester)[1], 0, reason: 'b’s wait till they’re gone');
      await tester.pump(Motion.standard * 0.5);
      expect(_layers(tester)[0], 0);
      expect(_layers(tester)[1], inExclusiveRange(0, 1), reason: 'b’s come');
      await tester.pumpAndSettle();
      expect(_layers(tester), [1]);
      expect(find.text('Not a git repository'), findsNothing);
      expect(find.text('dark-mode'), findsOneWidget);
      await closeView(tester, d);
    },
  );

  testWidgets('what never comes doesn’t keep the last chat’s rows past '
      'Waits.handover', (tester) async {
    final fake = FakeDaemon([
      Chat(id: 'a', agent: 'claude', folder: '/a'),
      Chat(id: 'b', agent: 'claude', folder: '/b'),
    ]);
    final d = await fake.connect(tester);
    final a = ChatState('a', '/a')..loaded = true;
    final b = ChatState('b', '/b');
    final picked = ValueNotifier(a);
    await _picking(tester, d, picked);
    await tester.pumpAndSettle();
    picked.value = b;
    await tester.pump();
    await tester.pump(Waits.handover);
    expect(_layers(tester), hasLength(2));
    await tester.pumpAndSettle();
    expect(_layers(tester), [1]);
    await closeView(tester, d);
  });
}

/// A DetailsPanel of the chat [picked] says.
Future<void> _picking(
  WidgetTester tester,
  Daemon d,
  ValueNotifier<ChatState> picked,
) => tester.pumpWidget(
  themed(
    ValueListenableBuilder(
      valueListenable: picked,
      builder: (context, chat, _) =>
          DetailsPanel(chat: chat, daemon: d, onChanges: () {}),
    ),
  ),
);

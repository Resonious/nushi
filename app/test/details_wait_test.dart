import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/details_panel.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/motion.dart';

import 'fake_daemon.dart';
import 'harness.dart';

// A chat just opened: the details panel doesn't flash "Not reported yet"
// and "…" for a frame or two, its rows folding and growing again as the
// numbers come. It waits for the chat's snapshot and its folder's status,
// Waits.slow at most, its rows unseen meanwhile.

/// How much of the panel's rows shows.
double _shown(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .descendant(
            of: find.byType(DetailsPanel),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

void main() {
  testWidgets('the rows wait for the chat and its folder, then show', (
    tester,
  ) async {
    final fake = FakeDaemon([Chat(id: 'c', agent: 'claude', folder: '/x')])
      ..answer = (input) => switch (input) {
        GetFolderStatusRequest() => Future.delayed(
          const Duration(milliseconds: 40),
          () => GetFolderStatusResponse(),
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
    expect(_shown(tester), 1);
    await closeView(tester, d);
  });
}

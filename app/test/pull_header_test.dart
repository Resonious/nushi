import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/github_checks.dart';
import 'package:nushi/github_files.dart';
import 'package:nushi/item_chats.dart';
import 'package:nushi/pull_commits.dart';
import 'package:nushi/pull_header.dart';
import 'package:nushi/pull_merge_card.dart';

import 'fake_daemon.dart';
import 'harness.dart';
import 'pull_fixture.dart';
import 'pull_overview_fixture.dart';

/// The page's bar, head and tabs.
void main() {
  setUpAll(loadFonts);

  test('the page: 1160 at most, centred; 32 at each side, 16 when narrow', () {
    expect(pullPad(1700), 270);
    expect(pullPad(1100), 32);
    expect(pullPad(720), 16);
  });

  testWidgets('the head: title, state, who opened it and when, base ← '
      'head, the size; the bar: #n and the title, Merge status and '
      'Submit review; no Start work in a chat', (tester) async {
    final (d, _) = await openPullTab(
      tester,
      overviewPull(),
      size: const Size(1700, 1000),
    );
    expect(find.text('#218'), findsWidgets); // and the chat's chip
    expect(
      find.text('Fix login redirect loop after session expiry'),
      findsNWidgets(2), // the bar's and the head's
    );
    expect(
      find.textContaining('mira opened 3h ago', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('fix-login-redirect'), findsOneWidget);
    expect(find.byTooltip('Open on GitHub'), findsOneWidget);
    expect(find.text('Submit review'), findsOneWidget);
    expect(find.text('Start work'), findsNothing);
    expect(find.byType(ItemChats), findsNothing);
    for (final t in [
      'Overview',
      'Commits  3',
      'Checks  2 failing',
      'Files changed  4',
    ]) {
      expect(find.text(t), findsOneWidget);
    }
    // The bar's buttons at its right edge.
    expect(
      tester.getRect(find.text('Submit review')).right,
      greaterThan(1700 - 60),
    );
    d.dispose();
  }, variant: onMac);

  testWidgets('Merge status: back to Overview, scrolled to the card, its '
      'first segment not met open', (tester) async {
    final (d, _) = await openPullTab(
      tester,
      overviewPull(),
      size: const Size(1700, 1000),
    );
    await tester.tap(find.text('Files changed  4'));
    await tester.pumpAndSettle();
    expect(find.byType(MergeCard), findsNothing);
    await tester.tap(find.text('Merge status'));
    await tester.pumpAndSettle();
    expect(find.byType(MergeCard), findsOneWidget);
    expect(
      find.textContaining('Failing after 41s', findRichText: true),
      findsOneWidget,
    );
    d.dispose();
  }, variant: onMac);

  testWidgets('scrolled past the head, the state pill joins the bar', (
    tester,
  ) async {
    final (d, _) = await openPullTab(
      tester,
      overviewPull(),
      size: const Size(1700, 1000),
    );
    final inBar = find.descendant(
      of: find.byType(PullBar),
      matching: find.text('Open'),
    );
    expect(inBar, findsNothing);
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(inBar, findsOneWidget);
    d.dispose();
  }, variant: onMac);

  for (final (tab, section) in [
    ('Checks  3 failing', GitHubChecks),
    ('Files changed  12', GitHubFiles),
    ('Commits  1', PullCommitsList),
  ]) {
    testWidgets('a tab shows its own: $tab', (tester) async {
      final (d, _) = await openPullTab(tester, fixturePull());
      expect(find.byType(section), findsNothing);
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.byType(section), findsOneWidget);
      d.dispose();
    }, variant: onMac);
  }

  testWidgets('narrow: the side column under the main one, nothing past '
      'the window', (tester) async {
    // Opened wide (narrow, the chat's tabs fold into a menu), then narrowed.
    final (d, _) = await openPullTab(
      tester,
      overviewPull(),
      size: const Size(1700, 1000),
      commits: overviewCommits(),
    );
    await narrowing(
      tester,
      from: 1100,
      to: 720,
      check: (width) {
        expect(tester.takeException(), isNull);
        expectTextInside(tester, width);
      },
      reopen: () async {},
    );
    expect(find.text('Status'), findsOneWidget);
    final side = tester.getRect(find.byKey(const ValueKey('pull-side')));
    final card = tester.getRect(find.byType(MergeCard));
    expect(side.top, greaterThan(card.bottom));
    d.dispose();
  }, variant: onMac);
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/github_card.dart';
import 'package:nushi/main.dart';
import 'package:nushi/pull_header.dart';
import 'package:nushi/pull_merge_card.dart';
import 'package:nushi/settings.dart';

import 'fake_daemon.dart';
import 'harness.dart';
import 'pull_fixture.dart';
import 'pull_overview_fixture.dart';

/// The page's head and its slim bar (ADR 0137): at rest Merge status and
/// Submit review end the title's row; once the title has scrolled away
/// the bar lies over the page's top, in the page's column, the same
/// buttons at the same right edge, its content still while it shows.
void main() {
  setUpAll(loadFonts);

  final bar = find.byType(PullBar);
  Finder inBar(String text) =>
      find.descendant(of: bar, matching: find.text(text));
  Finder inHead(String text) => find.descendant(
    of: find.byKey(const ValueKey('pull-header')),
    matching: find.text(text),
  );
  final scroll = find.byType(CustomScrollView).last;

  /// The tabs' line: the column's edges.
  Rect column(WidgetTester tester) => tester.getRect(
    find
        .ancestor(
          of: find.text('Overview'),
          matching: find.byWidgetPredicate(
            (w) => w is Column && w.key is GlobalKey,
          ),
        )
        .first,
  );

  /// Opened wide (narrow, the chat's tabs fold into a menu), then at
  /// [width].
  Future<Daemon> open(
    WidgetTester tester,
    double width, {
    bool sidebar = false,
  }) async {
    sidebarHidden.value = !sidebar;
    final (d, _) = await openPullTab(
      tester,
      overviewPull(),
      size: const Size(1700, 1000),
      commits: overviewCommits(),
    );
    viewport(tester, Size(width, 1000));
    await tester.pumpAndSettle();
    return d;
  }

  Future<void> scrollBy(WidgetTester tester, double dy) async {
    await tester.drag(scroll, Offset(0, -dy));
    await tester.pumpAndSettle();
  }

  /// Moves the page [dy] down at once (no drag's slop), a frame drawn.
  Future<void> step(WidgetTester tester, double dy) async {
    final at = tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position;
    at.jumpTo(at.pixels + dy);
    await tester.pump();
  }

  // The details and the side panes show only on the Chat tab; the
  // sidebar narrows the page's pane.
  for (final (width, sidebar) in [
    (1700.0, false),
    (1280.0, false),
    (900.0, false),
    (720.0, false),
    (1700.0, true),
    (1280.0, true),
  ]) {
    final name = '${width.toInt()}${sidebar ? ', sidebar' : ''}';
    testWidgets('$name: no bar at rest; the buttons end the title row at '
        "the column's right edge; scrolled, the bar's content in the "
        'same column, the buttons where they were', (tester) async {
      final d = await open(tester, width, sidebar: sidebar);
      expect(bar, findsNothing);
      final col = column(tester);
      final review = tester.getRect(inHead('Submit review'));
      final title = tester.getRect(
        inHead('Fix login redirect loop after session expiry'),
      );
      final card = tester.getRect(find.byType(MergeCard));
      expect(review.right, moreOrLessEquals(col.right - 12, epsilon: 0.01));
      expect(title.left, col.left);
      expect(card.left, col.left);
      final buttonRight = tester
          .getRect(
            find
                .ancestor(
                  of: inHead('Submit review'),
                  matching: find.byType(PullActions),
                )
                .first,
          )
          .right;
      expect(buttonRight, col.right);
      final shot = 'pull_head_${name.replaceAll(RegExp('[, ]+'), '_')}';
      await render(tester, find.byType(NushiApp), '${shot}_rest');

      await scrollBy(tester, 300);
      expect(bar, findsOneWidget);
      final pill = tester.getRect(
        find.descendant(of: bar, matching: find.byType(ItemStatePill)),
      );
      final barActions = tester.getRect(
        find.descendant(of: bar, matching: find.byType(PullActions)),
      );
      expect(pill.left, col.left);
      expect(barActions.right, col.right);
      expect(
        tester.getRect(inBar('Submit review')).left,
        review.left,
        reason: 'the button stays put across',
      );
      expect(tester.getRect(bar).width, greaterThan(col.width));
      expectTextInside(tester, width);
      await render(tester, find.byType(NushiApp), '${shot}_scrolled');
      d.dispose();
    }, variant: onMac);
  }

  testWidgets('scrolled a step at a time across the edge: the bar shows '
      'or not, its content the same in every frame it shows; no flicker '
      'at the edge', (tester) async {
    final d = await open(tester, 1700);
    Map<String, Rect>? first;
    var shows = 0;
    for (var i = 0; i < 30; i++) {
      await step(tester, 6);
      for (var f = 0; f < 4; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (bar.evaluate().isEmpty) continue;
        final now = {
          for (final w in [
            find.byType(ItemStatePill),
            find.text('#218'),
            find.text('Fix login redirect loop after session expiry'),
            find.text('Merge status'),
            find.text('Submit review'),
          ])
            w.describeMatch(Plurality.one): tester.getRect(
              find.descendant(of: bar, matching: w),
            ),
        };
        first ??= now;
        expect(now, first);
        shows++;
      }
    }
    expect(shows, greaterThan(0), reason: 'it came');
    // Back by less than the slack: it stays.
    await step(tester, -4);
    await tester.pumpAndSettle();
    final shown = bar.evaluate().isNotEmpty;
    await step(tester, 4);
    await tester.pumpAndSettle();
    expect(bar.evaluate().isNotEmpty, shown);
    // Back at the top it's gone, and the page never moved under it.
    final before = tester.getRect(find.byType(MergeCard));
    await tester.drag(scroll, const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(bar, findsNothing);
    expect(tester.getRect(find.byType(MergeCard)).top, greaterThan(before.top));
    d.dispose();
  }, variant: onMac);

  testWidgets('it comes and goes without moving the page', (tester) async {
    final d = await open(tester, 1700);
    var at = tester.getRect(find.byType(MergeCard)).top;
    var shown = false;
    for (var i = 0; i < 20 && !shown; i++) {
      await step(tester, 5);
      await tester.pump(const Duration(milliseconds: 16));
      final now = tester.getRect(find.byType(MergeCard)).top;
      expect(now, moreOrLessEquals(at - 5, epsilon: 0.01));
      at = now;
      shown = bar.evaluate().isNotEmpty;
    }
    expect(shown, isTrue);
    d.dispose();
  }, variant: onMac);

  testWidgets('under Reduce Motion it shows and goes at once', (tester) async {
    final d = await open(tester, 1700);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.drag(scroll, const Offset(0, -300));
    await tester.pump();
    await tester.pump();
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: bar, matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, 1);
    d.dispose();
  }, variant: onMac);

  for (final tab in [
    'Overview',
    'Commits  3',
    'Checks  2 failing',
    'Files changed  4',
  ]) {
    testWidgets('$tab: the same head, the bar over its top once scrolled, '
        'the tabs just under it', (tester) async {
      // Short, so every tab scrolls.
      final d = await open(tester, 1700);
      viewport(tester, const Size(1700, 360));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(inHead('Submit review'), findsOneWidget);
      // Picking a tab scrolls the tabs up, the bar over the page's top.
      final tabs = tester.getRect(find.text(tab));
      if (bar.evaluate().isNotEmpty) {
        expect(tabs.top, greaterThanOrEqualTo(tester.getRect(bar).bottom));
      }
      await scrollBy(tester, 300);
      expect(bar, findsOneWidget);
      d.dispose();
    }, variant: onMac);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/pull_comments.dart';
import 'package:nushi/pull_thread_card.dart';
import 'package:nushi/replies.dart';
import 'package:nushi/send_to_agent.dart';

import 'fake_daemon.dart';
import 'harness.dart';
import 'pull_overview_fixture.dart';

/// The Overview's Comments: reviews holding their threads, plain comments
/// between them in time, the filter, a bot's comment folded.
void main() {
  setUpAll(loadFonts);

  String say(CommentItem i) =>
      '${i.comment?.author ?? '-'} '
      '${i.comment?.review ?? ''}: '
      '${i.threads.map((x) => x.id).join(' ')}';

  test('each review holds its threads by review id, in time with the '
      "comments; a thread whose review isn't known comes on its own", () {
    final p = overviewPull();
    expect(commentItems(p).map(say), [
      'iris approved: T_test',
      'tomas changes_requested: T_session T_middleware',
      'mira : ',
    ]);
    // An older daemon: no review ids, the reviews from the conversation.
    final old = overviewPull()..reviews.clear();
    for (final x in old.threads) {
      for (final c in x.comments) {
        c.reviewId = '';
      }
    }
    expect(commentItems(old).map(say), [
      '- : T_test',
      '- : T_session',
      '- : T_middleware',
      'mira : ',
    ]);
  });

  test('a review that said nothing and holds no thread is left out', () {
    final p = overviewPull()
      ..reviews.add(
        GitHubComment(id: 'PRR_x', author: 'iris', review: 'commented'),
      );
    expect(commentItems(p), hasLength(3));
  });

  test('filters: Unresolved keeps only open threads, under their review; '
      'Mine what I wrote or answered', () {
    final items = commentItems(overviewPull());
    expect(filtered(items, CommentFilter.unresolved, 'mira').map(say), [
      'iris approved: T_test',
      'tomas changes_requested: T_session',
    ]);
    expect(filtered(items, CommentFilter.mine, 'Mira').map(say), [
      'tomas changes_requested: T_session',
      'mira : ',
    ]);
    expect(filtered(items, CommentFilter.mine, ''), isEmpty);
  });

  late List<(List<Reply>, String)> sent;

  Future<Daemon> comments(
    WidgetTester tester,
    GitHubPull p, {
    CommentFilter start = CommentFilter.all,
  }) async {
    var filter = start;
    sent = [];
    final d = await FakeDaemon([]).connect(tester);
    viewport(tester, const Size(900, 1600));
    final keys = <String, GlobalKey<PullThreadState>>{};
    await tester.pumpWidget(
      themed(
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SendToAgent(
            onSend: (r, what) => sent.add((r, what)),
            child: StatefulBuilder(
              builder: (context, setState) => PullComments(
                daemon: d,
                pull: p,
                me: 'mira',
                filter: filter,
                onFilter: (f) => setState(() => filter = f),
                onPosted: () async {},
                threadKeys: (id) => keys.putIfAbsent(id, GlobalKey.new),
                reviewKeys: (_) => GlobalKey(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return d;
  }

  testWidgets("a thread sits in its review's card; the filter narrows "
      'them', (tester) async {
    final d = await comments(tester, overviewPull());
    double y(Finder f) => tester.getTopLeft(f).dy;
    final review = find.textContaining('The fix is right', findRichText: true);
    final mira = find.textContaining('Moved it into', findRichText: true);
    final place = find.text('auth/session.go:46–47');
    expect(y(place), greaterThan(y(review)));
    expect(y(place), lessThan(y(mira)));
    await tester.tap(find.text('Unresolved'));
    await tester.pumpAndSettle();
    expect(find.text('auth/middleware.go:31'), findsNothing);
    expect(
      find.textContaining('Moved it into', findRichText: true),
      findsNothing,
    );
    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    expect(find.text('auth/session_test.go:12'), findsNothing);
    expect(
      find.textContaining('Moved it into', findRichText: true),
      findsOneWidget,
    );
    d.dispose();
  });

  testWidgets("a review's ⋯ sends it to the agent: changes requested as "
      'such; a thread its own card', (tester) async {
    final d = await comments(tester, overviewPull());
    await tester.tap(find.byTooltip('More').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to agent').first); // the menu's
    await tester.pumpAndSettle();
    expect(sent.single.$2, "@tomas' review");
    expect(sent.single.$1.single.from, 'Changes requested by @tomas');
    await tester.tap(find.text('Send to agent'));
    await tester.pumpAndSettle();
    expect(sent.last.$2, 'the thread on auth/session.go:46–47');
    expect(sent.last.$1.single.quote, contains('Good point, doing that now.'));
    d.dispose();
  });

  testWidgets("a bot's comment folds to its first words, Show opens it", (
    tester,
  ) async {
    final p = overviewPull()
      ..conversation.add(
        GitHubComment(
          id: 'IC_bot',
          author: 'preview-bot',
          bot: true,
          body: 'Deployed a preview.\n\nIt lives at preview.example.dev.',
          createdMs: msAgo(const Duration(minutes: 5)),
        ),
      );
    final d = await comments(tester, p);
    expect(
      find.textContaining('It lives at', findRichText: true),
      findsNothing,
    );
    await tester.tap(find.text('Show').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('It lives at', findRichText: true),
      findsOneWidget,
    );
    d.dispose();
  });
}

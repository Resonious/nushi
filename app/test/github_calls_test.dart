import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/main.dart';
import 'package:nushi/settings.dart';

import 'fake_daemon.dart';
import 'harness.dart';
import 'pull_fixture.dart';

/// The chats' pull requests: chat `c<n>`'s is #n, open, its checks passed.
GitHubLink _link(int n) => GitHubLink(
  host: 'github.com',
  repo: fixtureRepo,
  number: n,
  id: 'PR_$n',
  pull: true,
);

GitHubItem _item(int n, {String state = 'open'}) => GitHubItem(
  ref: GitHubRef(host: 'github.com', repo: fixtureRepo, number: n),
  id: 'PR_$n',
  pull: true,
  title: 'Change $n',
  state: state,
  checks: 'success',
  checksOid: 'c$n',
);

/// The app open on chat c1 of [chats] chats, each with its pull request
/// ([state] of each), its Chat tab showing; GitHub's answers from the
/// fake.
Future<(Daemon, FakeDaemon)> _open(
  WidgetTester tester, {
  int chats = 5,
  String state = 'open',
  bool details = true,
}) async {
  viewport(tester, const Size(1440, 900));
  showDetails.value = details;
  final whole = fixturePull();
  final list = [
    for (var n = 1; n <= chats; n++)
      chat('c$n', 'claude', 'Chat $n', folder: '/Users/me/project-$n')
        ..pull = _link(n)
        ..pulls.add(_link(n)),
  ];
  List<GitHubItem> items(Iterable<GitHubRef> refs) => [
    for (final r in refs) _item(r.number, state: state),
  ];
  final fake = FakeDaemon(list)
    ..answer = (input) => switch (input) {
      GetGitHubStatesRequest(:final items) => GetGitHubStatesResponse(
        items: [
          for (final l in items)
            _item(int.parse(l.id.substring(3)), state: state),
        ],
      ),
      GetGitHubItemsRequest(:final refs) => GetGitHubItemsResponse(
        items: items(refs),
      ),
      FindChatPullRequest(:final chatId) => FindChatPullResponse(
        host: 'github.com',
        repo: fixtureRepo,
        branch: 'work-$chatId',
        pull: _link(int.parse(chatId.substring(1))),
        pulls: [_link(int.parse(chatId.substring(1)))],
      ),
      GetGitHubPullRequest() => GetGitHubPullResponse(
        pull: whole.deepCopy()..item.state = state,
      ),
      GetGitHubCommitsRequest() => fixtureCommits(),
      ListGitHubHostsRequest() => ListGitHubHostsResponse(
        hosts: [GitHubHost(host: 'github.com', login: 'robin', source: 'gh')],
      ),
      _ => null,
    };
  final d = await fake.connect(tester);
  d.select('c1');
  await tester.pumpWidget(NushiApp(daemon: d));
  await tester.pumpAndSettle();
  return (d, fake);
}

/// The app's GitHub asks of the daemon over [minutes], by kind.
Future<Map<String, int>> _idle(
  WidgetTester tester,
  FakeDaemon fake, {
  int minutes = 60,
}) async {
  fake.calls.clear();
  for (var i = 0; i < minutes; i++) {
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
  }
  final out = <String, int>{};
  for (final c in fake.calls) {
    final kind = switch (c) {
      GetGitHubStatesRequest() => 'states',
      GetGitHubItemsRequest() => 'items',
      FindChatPullRequest() => 'find',
      GetGitHubPullRequest() => 'whole',
      _ => null,
    };
    if (kind != null) out[kind] = (out[kind] ?? 0) + 1;
  }
  return out;
}

void main() {
  setUpAll(loadFonts);

  // ADR 0140's counts: an idle hour with five chats, each with an open
  // pull request, one of them open on its Chat tab. Before it the app
  // asked each minute for the chats' states, the open chat's branch, its
  // rows and its pull request whole: 241 asks in the hour, each a request
  // to GitHub (the daemon keeps an answer 20 to 30 s). Now the chats'
  // rows, in one ask a minute.
  testWidgets("an idle hour asks for the chats' rows once a minute, in one "
      'ask, and nothing else', (tester) async {
    final (d, fake) = await _open(tester);
    expect(await _idle(tester, fake), {'items': 60});
    final last = fake.calls.whereType<GetGitHubItemsRequest>().last;
    expect(last.refs.map((r) => r.number), unorderedEquals([1, 2, 3, 4, 5]));
    d.dispose();
  }, variant: onMac);

  testWidgets('away from the window, every 5 minutes; back, at once', (
    tester,
  ) async {
    final (d, fake) = await _open(tester);
    final binding = tester.binding;
    addTearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final away = await _idle(tester, fake);
    expect(away.keys, ['items']);
    expect(away['items'], inInclusiveRange(12, 13));
    fake.calls.clear();
    await tester.pump(const Duration(minutes: 2));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fake.calls.whereType<GetGitHubItemsRequest>(), hasLength(1));
    d.dispose();
  }, variant: onMac);

  testWidgets('all merged: every 15 minutes, the branch looked up too', (
    tester,
  ) async {
    final (d, fake) = await _open(tester, state: 'merged');
    final calls = await _idle(tester, fake);
    expect(calls, {'items': 4, 'find': 4});
    d.dispose();
  }, variant: onMac);

  testWidgets('the Pull request tab reads its pull request whole each '
      'minute while it shows, and not after', (tester) async {
    final (d, fake) = await _open(tester);
    final c1 = d.chats['c1']!;
    fake.calls.clear();
    c1.tab.value = ChatTab.pull;
    await tester.pumpAndSettle();
    expect(fake.calls.whereType<GetGitHubPullRequest>(), hasLength(1));
    final shown = await _idle(tester, fake, minutes: 10);
    expect(shown['whole'], 10);
    c1.tab.value = ChatTab.chat;
    await tester.pumpAndSettle();
    final hidden = await _idle(tester, fake, minutes: 10);
    expect(hidden.containsKey('whole'), isFalse);
    d.dispose();
  }, variant: onMac);
}

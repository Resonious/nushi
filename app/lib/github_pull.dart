import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/github_checks.dart';
import 'package:nushi/github_files.dart';
import 'package:nushi/github_parts.dart';
import 'package:nushi/github_review.dart';
import 'package:nushi/item_chats.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/plain_tabs.dart';
import 'package:nushi/pull_cache.dart';
import 'package:nushi/pull_comments.dart';
import 'package:nushi/pull_commits.dart';
import 'package:nushi/pull_header.dart';
import 'package:nushi/pull_link.dart';
import 'package:nushi/pull_merge_card.dart';
import 'package:nushi/pull_merge_state.dart';
import 'package:nushi/pull_overview.dart';
import 'package:nushi/pull_skeleton.dart';
import 'package:nushi/pull_thread_card.dart';
import 'package:nushi/pull_todo_items.dart';
import 'package:nushi/review_findings.dart';
import 'package:nushi/run_state.dart';
import 'package:nushi/send_to_agent.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/widgets.dart';

/// How often an open pull request is asked for again (quietly), in the
/// GitHub view.
const pullPoll = Duration(seconds: 30);

/// Each pull request's tab (Overview, Commits, Checks, Files changed) as
/// left, while the app runs: a look at a chat comes back to it, and to
/// what was being written there.
final Map<String, PullSection> _tabLeft = runMap();

/// No pull request's tab left (tests: each starts afresh).
@visibleForTesting
void forgetPullTabs() => _tabLeft.clear();

/// Opens [ref]'s pull request at [section] the next time it shows (a
/// row's View changes, its badge's Show checks).
void openPullAt(GitHubRef ref, PullSection section) =>
    _tabLeft['${ref.host} ${ref.repo} ${ref.number}'] = section;

/// A pull request's page, after GitHub's own (ADR 0137): a slim bar (`#n`,
/// the title, Merge status, Submit review), the head ([PullHeader]: the
/// title, state, who opened it, base ← head), the tabs (Overview,
/// Commits, Checks, Files changed) and the tab's content in one scroll,
/// in a column of [pullPageWidth] at most; the files' diff the whole
/// width and the window's height.
///
/// In a chat's Pull request tab it shows the chat's pull request as
/// [source] has it, asked on its timer (the pane has none of its own),
/// with no Start work or chats' links (the chat is the one); its comments
/// are seen while it shows.
class GitHubPullPane extends StatefulWidget {
  const new({required this.daemon, required this.ref, super.key, this.source});

  final Daemon daemon;
  final GitHubRef ref;

  /// The chat's pull request, in its Pull request tab.
  final ChatPull? source;

  @override
  State<GitHubPullPane> createState() => _GitHubPullPaneState();
}

class _GitHubPullPaneState extends State<GitHubPullPane> {
  /// What shows in the GitHub view: the pull request read last (kept from
  /// before, from [_keptAt], until the first answer), else nothing yet
  /// (the skeleton). In a chat's tab its [GitHubPullPane.source]'s.
  late GitHubPull? _pull = _kept?.$2;
  late final (DateTime, GitHubPull)? _kept = widget.source == null
      ? cachedPull(widget.ref)
      : null;
  late DateTime? _keptAt = _kept?.$1;
  bool _asking = true;
  String? _error;
  Timer? _poll;
  late PullSection _tab = _tabLeft[_refKey] ?? PullSection.overview;
  String get _refKey =>
      '${widget.ref.host} ${widget.ref.repo} ${widget.ref.number}';
  final _scroll = ScrollController();
  final GlobalKey _tabs = GlobalKey();
  final _mergeKey = GlobalKey<MergeCardState>();
  final _threadKeys = <String, GlobalKey<PullThreadState>>{};
  final _reviewKeys = <String, GlobalKey>{};
  CommentFilter _filter = CommentFilter.all;
  late final PullCommits _commits = PullCommits(widget.daemon, widget.ref);

  /// The header has scrolled away: the bar shows the state pill.
  final ValueNotifier<bool> _scrolled = ValueNotifier(false);

  /// Who the user is on its host ('' until known).
  String _me = '';

  bool get _inChat => widget.source != null;

  @override
  void initState() {
    super.initState();
    if (widget.source case final s?) {
      s.addListener(_sourceChanged);
      // Asked as the tab opens, unless it was a moment ago.
      unawaited(s.refresh(again: false));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) s.markSeen();
      });
    } else {
      unawaited(_load());
      _poll = Timer.periodic(pullPoll, (_) => unawaited(_load(quiet: true)));
    }
    unawaited(
      githubLogin(widget.daemon, widget.ref.host).then((me) {
        if (mounted) setState(() => _me = me);
      }),
    );
    _redraw.addListener(_changed);
    _scroll.addListener(
      () => _scrolled.value = _scroll.hasClients && _scroll.offset > 90,
    );
  }

  void _changed() => setState(() {});

  /// The chat's pull request was asked for: its comments are seen.
  void _sourceChanged() {
    widget.source?.markSeen();
    setState(() {});
  }

  @override
  void dispose() {
    _tabLeft[_refKey] = _tab;
    widget.source?.removeListener(_sourceChanged);
    _redraw.removeListener(_changed);
    _poll?.cancel();
    _scroll.dispose();
    _scrolled.dispose();
    _commits.dispose();
    super.dispose();
  }

  /// Asks for the pull request again (it changed here): the chat's, or
  /// the pane's own.
  Future<void> _refresh() async {
    final s = widget.source;
    if (s == null) return await _load();
    await s.again();
  }

  /// The newest [_load]'s number: an older answer (a poll overtaken by the
  /// reload after a merge or a post) is dropped.
  int _asked = 0;

  Future<void> _load({bool quiet = false}) async {
    final n = ++_asked;
    try {
      final r = await widget.daemon.client.getGitHubPull(
        GetGitHubPullRequest(ref: widget.ref, quiet: quiet),
      );
      if (n != _asked) return;
      keepPull(widget.ref, r.pull);
      if (mounted) {
        setState(() {
          _pull = r.pull;
          _keptAt = null;
          _error = null;
        });
      }
    } on Object catch (e) {
      // A failed poll keeps what shows, and says why.
      if (mounted && n == _asked) setState(() => _error = errorText(e));
    } finally {
      if (mounted && n == _asked && _asking) {
        setState(() => _asking = false);
      }
    }
  }

  /// Scrolls [key]'s widget into view, after this frame.
  void _toView(GlobalKey key) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final to = key.currentContext;
        if (to == null || !to.mounted) return;
        Scrollable.ensureVisible(
          to,
          duration: Motion.standard,
          curve: Curves.easeOutCubic,
        );
      });

  /// Shows tab [s], scrolled up to the tabs.
  void _jump(PullSection s) {
    setState(() => _tab = s);
    _toView(_tabs);
  }

  /// The bar's Merge status: the card, its first segment not met open.
  void _mergeStatus() {
    setState(() => _tab = PullSection.overview);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _mergeKey.currentState?.reveal(),
    );
    _toView(_mergeKey);
  }

  /// A thread's row in the merge status card: the thread, open.
  void _showThread(GitHubThread x) {
    setState(() {
      if (_filter == CommentFilter.mine) _filter = CommentFilter.all;
    });
    final key = _threadKey(x.id);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => key.currentState?.show(),
    );
    _toView(key);
  }

  /// A finding's row: the review it's in.
  void _showReview(String id) {
    setState(() => _filter = CommentFilter.all);
    _toView(_reviewKey(id));
  }

  GlobalKey<PullThreadState> _threadKey(String id) =>
      _threadKeys.putIfAbsent(id, GlobalKey<PullThreadState>.new);
  GlobalKey _reviewKey(String id) => _reviewKeys.putIfAbsent(id, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final (pull, keptAt, asking, error) = switch (widget.source) {
      final s? => (s.pull, s.keptAt, s.asking, s.error),
      null => (_pull, _keptAt, _asking, _error),
    };
    final p = pull;
    if (p == null) {
      return error == null
          ? const PullSkeleton()
          : Center(child: Text(error, style: theme.ui(t.crashed)));
    }
    if (_tab == PullSection.overview || _tab == PullSection.commits) {
      _commits.want(p.headOid);
    }
    final failed = p.checks.where((c) => c.failed).length;
    final todo = todoOf(p);
    final open = p.item.state == 'open';
    return LayoutBuilder(
      builder: (context, box) {
        final pad = pullPad(box.maxWidth);
        final narrow = box.maxWidth < pullNarrow;
        Widget column(Widget child, {double top = 0, double bottom = 0}) =>
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, top, pad, bottom),
              sliver: SliverToBoxAdapter(child: child),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PullBar(
              pull: p,
              scrolled: _scrolled,
              actions: _actions(context, p),
              onMergeStatus: open && mergeView(p) != null ? _mergeStatus : null,
            ),
            Expanded(
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  if (keptAt case final at?)
                    column(
                      Text(
                        updatedLine(at, loading: asking)!,
                        key: const ValueKey('pull-kept'),
                        textAlign: TextAlign.right,
                        style: theme.ui(t.textMuted, size: 11.5),
                      ),
                      top: 8,
                    ),
                  column(PullHeader(pull: p), top: keptAt == null ? 24 : 4),
                  if (error case final e?)
                    column(
                      Text(
                        'Not current: $e',
                        style: theme.ui(t.needs, size: 12),
                      ),
                      top: 6,
                    ),
                  column(
                    Column(
                      key: _tabs,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: PlainTabs(
                              value: _tab,
                              tabs: [
                                (PullSection.overview, 'Overview'),
                                (PullSection.commits, 'Commits  ${p.commits}'),
                                (
                                  PullSection.checks,
                                  failed > 0
                                      ? 'Checks  $failed failing'
                                      : 'Checks  ${p.checks.length}',
                                ),
                                (
                                  PullSection.files,
                                  'Files changed  ${p.changedFiles}',
                                ),
                              ],
                              onChanged: _jump,
                            ),
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: t.line),
                      ],
                    ),
                    top: 16,
                    bottom: 20,
                  ),
                  switch (_tab) {
                    PullSection.commits => column(
                      PullCommitsList(commits: _commits),
                      bottom: 24,
                    ),
                    PullSection.checks => column(
                      GitHubChecks(
                        daemon: widget.daemon,
                        pull: p,
                        onChanged: _refresh,
                      ),
                      bottom: 20,
                    ),
                    PullSection.files => SliverToBoxAdapter(
                      // The window's height, under the tabs: the list and
                      // the diff scroll in it.
                      child: SizedBox(
                        height: box.maxHeight - 84,
                        child: GitHubFiles(
                          daemon: widget.daemon,
                          pull: p,
                          onChanged: _refresh,
                        ),
                      ),
                    ),
                    PullSection.overview => column(
                      PullOverview(
                        daemon: widget.daemon,
                        pull: p,
                        todo: todo,
                        me: _me,
                        narrow: narrow,
                        commits: _commits,
                        filter: _filter,
                        onFilter: (f) => setState(() => _filter = f),
                        onChanged: _refresh,
                        onCommits: () => _jump(PullSection.commits),
                        onThread: _showThread,
                        onReview: _showReview,
                        mergeKey: _mergeKey,
                        threadKeys: _threadKey,
                        reviewKeys: _reviewKey,
                        stale: keptAt != null,
                        sideTop: _inChat
                            ? null
                            : ItemChats(widget.daemon, p.item.ref),
                      ),
                      bottom: 48,
                    ),
                  },
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// The bar's buttons: Start work (the GitHub view), Submit review.
  List<Widget> _actions(BuildContext context, GitHubPull p) {
    final it = p.item;
    final pending = p.pendingComments + reviewDrafts(it.ref).length;
    return [
      if (!_inChat) StartWork(daemon: widget.daemon, item: it),
      Button(
        label: pending > 0 ? 'Submit review ($pending)' : 'Submit review',
        tooltip: 'Comment, approve or request changes',
        onPressed: () => _review(context, p),
      ),
    ];
  }

  /// Opens the review dialog; who I am is asked then, as a token changed
  /// in Settings while this pane shows can be another account's.
  Future<void> _review(BuildContext context, GitHubPull p) async {
    final me = await githubLogin(widget.daemon, p.item.ref.host);
    if (!context.mounted) return;
    await submitReview(
      context,
      widget.daemon,
      p,
      onDone: _refresh,
      mine: me.isNotEmpty && me.toLowerCase() == p.item.author.toLowerCase(),
    );
  }
}

/// What redraws the pane: Settings' Findings from review bots (the To
/// do list), and the review's drafts (Review (n)…).
final _redraw = Listenable.merge([
  githubFindings,
  githubFindingBots,
  githubFindingHeadings,
  draftsChanged,
]);

/// What blocks [p]'s merge for the agent ([todo]), with the bots' findings
/// when Settings reads them.
Todo todoOf(GitHubPull p) => todo(
  p,
  findings: githubFindings.value
      ? findingsSetup(githubFindingBots.value, githubFindingHeadings.value)
      : null,
);

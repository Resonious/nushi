import 'package:flutter/material.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/github_comment.dart';
import 'package:nushi/github_parts.dart';
import 'package:nushi/markdown.dart';
import 'package:nushi/pull_comments.dart';
import 'package:nushi/pull_commits.dart';
import 'package:nushi/pull_merge_card.dart';
import 'package:nushi/pull_side.dart';
import 'package:nushi/pull_thread_card.dart';
import 'package:nushi/pull_todo_items.dart';
import 'package:nushi/theme/theme.dart';

/// The Overview tab, after GitHub's page (ADR 0137): the main column (the
/// merge status card, the description, the comments, the commit trail)
/// and the side column beside it, or under it when [narrow].
class PullOverview extends StatelessWidget {
  const new({
    required this.daemon,
    required this.pull,
    required this.todo,
    required this.me,
    required this.narrow,
    required this.commits,
    required this.filter,
    required this.onFilter,
    required this.onChanged,
    required this.onCommits,
    required this.onThread,
    required this.onReview,
    required this.mergeKey,
    required this.threadKeys,
    required this.reviewKeys,
    super.key,
    this.stale = false,
    this.sideTop,
  });

  final Daemon daemon;
  final GitHubPull pull;
  final Todo todo;
  final String me;
  final bool narrow;
  final PullCommits commits;
  final CommentFilter filter;
  final ValueChanged<CommentFilter> onFilter;
  final Future<void> Function() onChanged;
  final VoidCallback onCommits;
  final ValueChanged<GitHubThread> onThread;
  final ValueChanged<String> onReview;
  final GlobalKey<MergeCardState> mergeKey;
  final GlobalKey<PullThreadState> Function(String id) threadKeys;
  final GlobalKey Function(String id) reviewKeys;
  final bool stale;

  /// What tops the side column (the GitHub view's chats on the item).
  final Widget? sideTop;

  @override
  Widget build(BuildContext context) {
    final p = pull;
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeCard(
          key: mergeKey,
          daemon: daemon,
          pull: p,
          items: todo.items,
          stale: stale,
          onChanged: onChanged,
          onThread: onThread,
          onReview: onReview,
        ),
        const SizedBox(height: 20),
        PullDescription(p),
        const SizedBox(height: 32),
        PullComments(
          daemon: daemon,
          pull: p,
          me: me,
          filter: filter,
          onFilter: onFilter,
          onPosted: onChanged,
          threadKeys: threadKeys,
          reviewKeys: reviewKeys,
          items: todo.items,
          older: todo.older,
        ),
        const SizedBox(height: 20),
        CommitTrail(commits: commits, onAll: onCommits),
      ],
    );
    final side = PullSide(pull: p, onCommits: onCommits, top: sideTop);
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [main, const SizedBox(height: 32), side],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        const SizedBox(width: 32),
        SizedBox(width: 270, child: side),
      ],
    );
  }
}

/// The description: the pull request's text alone on a card.
class PullDescription extends StatelessWidget {
  const new(this.pull, {super.key});

  final GitHubPull pull;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    return Container(
      key: const ValueKey('pull-description'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: cardBox(t),
      child: pull.body.isEmpty
          ? Text('No description', style: theme.ui(t.textMuted, size: 12))
          : SelectionArea(
              child: AgentMarkdown(githubText(pull.body), images: githubImage),
            ),
    );
  }
}

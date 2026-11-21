import 'package:flutter/material.dart';
import 'package:nushi/clock.dart';
import 'package:nushi/commits.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/github_items.dart';
import 'package:nushi/jira_people.dart' show Avatar;
import 'package:nushi/line_icons.dart';
import 'package:nushi/theme/theme.dart';

/// An item's state as GitHub draws it (ADR 0117): its icon and color. A
/// pull request open green (a draft grey), merged violet, closed red; an
/// issue open green, closed as completed violet, as not planned grey.
/// Without [it], [pull]'s open icon, muted.
(LineIcon, Color) itemLook(Tokens t, GitHubItem? it, {required bool pull}) {
  if (it == null) {
    return (pull ? LineIcon.pullOpen : LineIcon.issueOpen, t.textMuted);
  }
  if (it.pull) {
    return switch (it.state) {
      'merged' => (LineIcon.pullMerged, t.subagentAccent),
      'closed' => (LineIcon.pullClosed, t.crashed),
      _ when it.draft => (LineIcon.pullDraft, t.textMuted),
      _ => (LineIcon.pullOpen, t.done),
    };
  }
  return switch (it.state) {
    'closed' when it.stateReason == 'not_planned' => (
      LineIcon.issueNotPlanned,
      t.textMuted,
    ),
    'closed' => (LineIcon.issueDone, t.subagentAccent),
    _ => (LineIcon.issueOpen, t.done),
  };
}

/// An item's state's icon, [size] square.
class ItemIcon extends StatelessWidget {
  const new(this.item, {required this.pull, super.key, this.size = 14});

  final GitHubItem? item;
  final bool pull;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = itemLook(NushiTheme.of(context).t, item, pull: pull);
    return icon.view(size: size, color: color);
  }
}

/// An item's state as a pill's word: Open, Draft, Merged, Closed, Not
/// planned.
String stateWord(GitHubItem it) => switch (it.state) {
  'merged' => 'Merged',
  'closed' when !it.pull && it.stateReason == 'not_planned' => 'Not planned',
  'closed' => 'Closed',
  _ => it.draft ? 'Draft' : 'Open',
};

/// What the hover card, a row and the transcript's card show of a pull
/// request's size: `+adds −dels`.
Widget diffSize(NushiTheme theme, GitHubItem it, {double size = 11.5}) {
  final t = theme.t;
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '+${it.additions}',
          style: theme.code(t.done, size: size),
        ),
        const TextSpan(text: ' '),
        TextSpan(
          text: '−${it.deletions}',
          style: theme.code(t.crashed, size: size),
        ),
      ],
    ),
    maxLines: 1,
  );
}

/// "3 files", "1 file".
String filesWords(int n) => '$n file${n == 1 ? '' : 's'}';

/// The hover card of a pull request's or an issue's link (ADR 0117): the
/// state pill, `owner/repo #n`, its age; the title (two lines at most);
/// the author and the size (or an issue's comments). No buttons. With
/// nothing to show it says why: GitHub doesn't show it to the account,
/// sign in, couldn't ask (with the last known and its age), or asking.
class GitHubCard extends StatelessWidget {
  const new(this.address, this.look, {super.key, this.width = 320});

  final GitHubAddress address;
  final GitHubLook look;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: floatBox(t, radius: NushiTheme.card),
      child: GitHubCardBody(address, look),
    );
  }
}

/// [GitHubCard]'s inside, for a card or a sheet.
class GitHubCardBody extends StatelessWidget {
  const new(this.address, this.look, {super.key});

  final GitHubAddress address;
  final GitHubLook look;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final a = address;
    final muted = theme.ui(t.textMuted, size: 12);
    final it = look.item;
    final head = '${a.repo} #${a.number}';
    if (it == null) {
      final why = look.unseen
          ? "${a.host} doesn't show this to your account: a private "
                'repository, or none by that name.'
          : look.signIn
          ? 'Sign in to GitHub to see it: Settings › GitHub.'
          : look.error != null
          ? "Couldn't ask GitHub: ${look.error}"
          : 'Asking GitHub…';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Row(
            spacing: 6,
            children: [
              ItemIcon(null, pull: a.pull),
              Flexible(
                child: Text(
                  head,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.code(t.textSecondary, size: 12),
                ),
              ),
            ],
          ),
          Text(why, style: muted),
        ],
      );
    }
    final now = clock();
    final when = it.createdMs > 0 ? it.createdMs : it.updatedMs;
    final at = look.at;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          spacing: 8,
          children: [
            ItemStatePill(it),
            Expanded(
              child: Text(
                head,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.code(t.textSecondary, size: 12),
              ),
            ),
            if (when > 0)
              Text(
                agoShort(
                  now.difference(
                    DateTime.fromMillisecondsSinceEpoch(when.toInt()),
                  ),
                ),
                style: muted,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          it.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.ui(t.text, weight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          spacing: 6,
          children: [
            Avatar(
              name: it.author,
              id: it.author,
              size: 16,
              letters: 1,
              tip: false,
            ),
            Expanded(
              child: Text(
                it.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.ui(t.textSecondary, size: 12),
              ),
            ),
            if (it.pull) ...[
              diffSize(theme, it),
              const SizedBox(width: 2),
              Text(filesWords(it.changedFiles), style: muted),
            ] else
              Text(
                '${it.comments} comment${it.comments == 1 ? '' : 's'}',
                style: muted,
              ),
          ],
        ),
        if (look.error != null && at != null) ...[
          const SizedBox(height: 8),
          Text(
            "Couldn't ask GitHub. As it was ${ago(now.difference(at), at)}.",
            style: muted,
          ),
        ],
      ],
    );
  }
}

/// An item's state as a pill: GitHub's icon and word on the state's soft
/// fill (ADR 0117: the hover card, the transcript's card).
class ItemStatePill extends StatelessWidget {
  const new(this.item, {super.key});

  final GitHubItem item;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final (icon, fg) = itemLook(t, item, pull: item.pull);
    final bg = fg == t.done
        ? t.doneSoft
        : fg == t.crashed
        ? t.crashedSoft
        : fg == t.subagentAccent
        ? t.subagentTint
        : t.selected;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 1, 8, 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NushiTheme.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          icon.view(size: 13, color: fg),
          Text(
            stateWord(item),
            style: theme.ui(fg, size: 12, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

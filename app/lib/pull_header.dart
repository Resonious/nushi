import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nushi/clock.dart';
import 'package:nushi/commits.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/github_card.dart';
import 'package:nushi/github_comment.dart';
import 'package:nushi/github_parts.dart';
import 'package:nushi/pull_lights.dart';
import 'package:nushi/pull_merge_card.dart';
import 'package:nushi/pull_side.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/widgets.dart';

export 'package:nushi/pull_lights.dart';

/// The widest the pull request's page is: its main column and side
/// column, centred, as GitHub's.
const pullPageWidth = 1160.0;

/// Below this the side column goes under the main one.
const pullNarrow = 1000.0;

/// The space at each side of the page in a pane [width] wide.
double pullPad(double width) =>
    math.max((width - pullPageWidth) / 2, width < pullNarrow ? 16.0 : 32.0);

/// The bar over the page: `#n` and the title (the state pill joins them
/// once the header has scrolled away, [scrolled]); at its right Merge
/// status (an open pull request's: shows the merge status card,
/// [onMergeStatus]) and [actions] (Submit review; Start work in the
/// GitHub view).
class PullBar extends StatelessWidget {
  const new({
    required this.pull,
    required this.scrolled,
    required this.actions,
    super.key,
    this.onMergeStatus,
  });

  final GitHubPull pull;
  final ValueListenable<bool> scrolled;
  final List<Widget> actions;
  final VoidCallback? onMergeStatus;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final it = pull.item;
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < pullNarrow;
        final head = mergeHead(pull);
        return Container(
          height: 44,
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 16 : NushiTheme.gutter,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Row(
            spacing: 8,
            children: [
              ValueListenableBuilder(
                valueListenable: scrolled,
                builder: (context, on, _) =>
                    on ? ItemStatePill(it) : const SizedBox.shrink(),
              ),
              Text('#${it.ref.number}', style: theme.ui(t.textMuted)),
              Expanded(
                child: Text(
                  it.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.ui(t.text, weight: FontWeight.w600),
                ),
              ),
              if (onMergeStatus != null)
                Button(
                  label: narrow ? 'Status' : 'Merge status',
                  icon: switch (head.mood) {
                    Mood.ok => Icons.check_circle_outline,
                    Mood.bad => Icons.cancel_outlined,
                    Mood.warn => Icons.error_outline,
                    Mood.quiet => Icons.schedule,
                  },
                  tooltip: 'Show the merge status',
                  onPressed: onMergeStatus,
                ),
              ...actions,
            ],
          ),
        );
      },
    );
  }
}

/// The page's head: the title (selectable) and Open on GitHub; under it
/// the state pill, who opened it and when, base ← head and the diff's
/// size.
class PullHeader extends StatelessWidget {
  const new({required this.pull, super.key});

  final GitHubPull pull;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final p = pull;
    final it = p.item;
    Widget branch(String name) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(NushiTheme.tag),
      ),
      child: SelectableText(name, style: theme.code(t.accentInk, size: 12)),
    );
    final opened = it.createdMs.toInt() != 0 ? it.createdMs : it.updatedMs;
    return Column(
      key: const ValueKey('pull-header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                it.title,
                style: theme.ui(t.text, size: 20, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            IconTap.line(
              LineIcon.openOutside,
              tooltip: 'Open on GitHub',
              onTap: it.url.isEmpty ? null : () => openWeb(context, it.url),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ItemStatePill(it),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                PersonMark(it.author, size: 18),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: it.author,
                        style: theme.ui(t.text, weight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: ' opened ${agoAt(opened.toInt(), clock())}',
                      ),
                    ],
                  ),
                  style: theme.ui(t.textMuted),
                ),
                if (p.outside) const OutsideMark(),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                branch(p.base),
                Icon(Icons.arrow_back, size: 14, color: t.textMuted),
                branch(p.crossRepo ? '${p.headRepo}:${p.head}' : p.head),
              ],
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '+${p.additions}',
                    style: theme.code(t.done, size: 12),
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: '−${p.deletions}',
                    style: theme.code(t.crashed, size: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nushi/clock.dart';
import 'package:nushi/commits.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/github_card.dart';
import 'package:nushi/github_comment.dart';
import 'package:nushi/github_parts.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/pull_edit.dart';
import 'package:nushi/pull_lights.dart';
import 'package:nushi/pull_merge_card.dart';
import 'package:nushi/pull_side.dart';
import 'package:nushi/slides.dart';
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

/// The slim bar's height.
const pullBarHeight = 44.0;

/// The page's buttons, at the end of its title row and of [PullBar], at
/// the same right edge (ADR 0137): Merge status (an open pull request's:
/// shows the merge status card, [onMergeStatus]) and [actions] (Submit
/// review; Start work in the GitHub view).
class PullActions extends StatelessWidget {
  const new({
    required this.pull,
    required this.narrow,
    required this.actions,
    super.key,
    this.onMergeStatus,
  });

  final GitHubPull pull;
  final bool narrow;
  final List<Widget> actions;
  final VoidCallback? onMergeStatus;

  @override
  Widget build(BuildContext context) {
    final head = mergeHead(pull);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
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
    );
  }
}

/// The slim bar that stands in for the head once its title has scrolled
/// out of view: the state pill, `#n`, the title on one line and
/// [actions] ([PullActions]), in the page's column ([pad] at each side,
/// so its ends meet the title's, the tabs' and the cards'), on the
/// pane's fill across the pane with a hairline under. Its content never
/// changes while it shows; scrolling only shows or hides it whole.
class PullBar extends StatelessWidget {
  const new({
    required this.pull,
    required this.pad,
    required this.actions,
    super.key,
  });

  final GitHubPull pull;
  final double pad;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final it = pull.item;
    return Container(
      height: pullBarHeight,
      padding: EdgeInsets.symmetric(horizontal: pad),
      decoration: BoxDecoration(
        color: t.base,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        spacing: 8,
        children: [
          ItemStatePill(it),
          Text('#${it.ref.number}', style: theme.ui(t.textMuted)),
          Expanded(
            child: Text(
              it.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.ui(t.text, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          actions,
        ],
      ),
    );
  }
}

/// [PullBar] over the top of the page's scroll ([scroll]), shown only
/// while the head's title row ([titleKey]) is out of view: it comes once
/// the row's bottom has gone under the bar's and goes once it's
/// a little further below again, so a title resting at the edge doesn't
/// flicker.
/// It fades in and out, at once under Reduce Motion, and lies over the
/// scroll, so nothing under it moves.
class StickyPullBar extends StatefulWidget {
  const new({
    required this.scroll,
    required this.titleKey,
    required this.bar,
    super.key,
  });

  final ScrollController scroll;
  final GlobalKey titleKey;
  final PullBar bar;

  @override
  State<StickyPullBar> createState() => _StickyPullBarState();
}

class _StickyPullBarState extends State<StickyPullBar> {
  /// How far past the bar's bottom the title row comes back before the
  /// bar goes.
  static const _slack = 6.0;

  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_later);
    _later();
  }

  @override
  void didUpdateWidget(StickyPullBar old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll.removeListener(_later);
      widget.scroll.addListener(_later);
    }
    // The page under it may have moved (a line above the head gone).
    _later();
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_later);
    super.dispose();
  }

  bool _asked = false;

  /// Checks once the frame's laid out: a scroll tells before the page
  /// has moved.
  void _later() {
    if (_asked) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _asked = false;
      _check();
    });
  }

  void _check() {
    if (!mounted) return;
    final row = widget.titleKey.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    // The row laid out away (another tab's slivers past the cache): the
    // page is scrolled past it, so the bar shows.
    var shown = row is! RenderBox || !row.attached;
    if (!shown && me is RenderBox && me.attached) {
      final bottom = row.localToGlobal(Offset(0, row.size.height)).dy;
      final under = bottom - me.localToGlobal(Offset.zero).dy;
      shown = _shown ? under < pullBarHeight + _slack : under < pullBarHeight;
    }
    if (shown != _shown) setState(() => _shown = shown);
  }

  @override
  Widget build(BuildContext context) => Presence(
    enter: Motion.quick,
    curve: Curves.easeOut,
    builder: (context, run, child) =>
        FadeTransition(opacity: run, child: child),
    child: _shown ? widget.bar : null,
  );
}

/// The page's head: the title (selectable; [PullTitle], with Edit when
/// GitHub lets the user), Open on GitHub beside it
/// and [actions] ([PullActions]) at the row's right end; under it the
/// state pill, who opened it and when, base ← head and the diff's size.
/// [titleKey] marks the title's row, which the slim bar watches.
class PullHeader extends StatelessWidget {
  const new({
    required this.daemon,
    required this.pull,
    required this.actions,
    required this.onSaved,
    super.key,
    this.titleKey,
  });

  final Daemon daemon;
  final GitHubPull pull;

  /// The title was edited: the pull request is read again.
  final Future<void> Function() onSaved;
  final Widget actions;
  final Key? titleKey;

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
          key: titleKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PullTitle(
                daemon: daemon,
                pull: p,
                onSaved: onSaved,
                trailing: IconTap.line(
                  LineIcon.openOutside,
                  tooltip: 'Open on GitHub',
                  onTap: it.url.isEmpty ? null : () => openWeb(context, it.url),
                ),
              ),
            ),
            const SizedBox(width: 12),
            actions,
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

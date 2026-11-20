import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:nushi/chat.dart';
import 'package:nushi/collapsible.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/drawn.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/subagents.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/widgets.dart';
import 'package:nushi/workflows.dart';

/// A workflow where its call is in the transcript (ADR 0127): a row on the
/// subagents' soft tint, as a subagent's, no outline, that says each
/// thing once (#103): its name, then where it is and how long, live
/// ("Review 5/7 · 3 running · 4m 12s"), in a subagent row's order, at the
/// line's end. Narrow, the state takes a line of its own. How a run that
/// didn't end well ended has a line under it. A click opens its pane (the
/// accent's soft fill while open; the failures' soft red once it failed);
/// under the pointer, a running one's mark becomes its Stop, in the same
/// room. On the phone ([Daemon.remote]) it opens nothing and has no Stop:
/// the chat's sheet stops it.
class WorkflowCard extends StatelessWidget {
  const new(this.call, this.chat, {super.key, this.daemon, this.still = false});

  final Item call;
  final ChatState chat;

  /// The daemon to stop it through; none, no Stop.
  final Daemon? daemon;

  /// No shine and no ticking (a golden, a waiting chat).
  final bool still;

  /// Below this width the state has a line of its own (a phone's
  /// transcript).
  static const narrow = 480.0;

  /// Where the lines under the name start: past the icon.
  static const double indent = 15 + 8;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final w = call.workflow;
    final phone = daemon?.remote ?? false;
    final failed = w.state == 'failed';
    final live = workflowLive(w);
    final ended = workflowEndWords(w);
    return Hover(
      builder: (context, {required hover}) => ValueListenableBuilder(
        valueListenable: chat.pane,
        builder: (context, open, _) => Tap(
          onTap: phone ? null : () => chat.pane.value = call.id,
          tooltip: phone ? '' : 'Open its agents',
          tint: !phone,
          fill: failed
              ? t.crashedSoft
              : open == call.id && !phone
              ? t.accentSoft
              : t.subagentTint,
          padding: const EdgeInsets.symmetric(horizontal: Collapsible.side),
          child: LayoutBuilder(
            builder: (context, box) {
              final narrow = box.maxWidth < WorkflowCard.narrow;
              final state = LiveText(
                () => workflowState(w),
                live: live && !w.stalled && !still,
                style: theme.ui(
                  failed
                      ? t.crashed
                      : w.stalled
                      ? t.needs
                      : t.textSecondary,
                  size: 12,
                ),
              );
              final name = Row(
                spacing: 8,
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 15,
                    color: failed ? t.crashed : t.subagentAccent,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Shine(
                        on: live && !w.stalled && !still,
                        child: workflowName(context, call),
                      ),
                    ),
                  ),
                  // The name takes the room; the state ends its line,
                  // half of the card at most.
                  if (!narrow)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.min(360, box.maxWidth / 2),
                      ),
                      child: state,
                    ),
                ],
              );
              final under = [
                if (narrow) state,
                if (ended.isNotEmpty)
                  Text(
                    ended,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.ui(failed ? t.crashed : t.textMuted, size: 12),
                  ),
              ];
              // One line as a subagent's row; with more, its mark and
              // chevron stay at the middle of its end.
              return ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: Collapsible.height,
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: under.isEmpty
                          ? SizedBox(height: Collapsible.height, child: name)
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 2,
                                children: [
                                  SizedBox(height: 20, child: name),
                                  for (final line in under)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: WorkflowCard.indent,
                                      ),
                                      child: line,
                                    ),
                                ],
                              ),
                            ),
                    ),
                    // The mark and its Stop share one room, so neither
                    // moves the state as the pointer comes and goes.
                    SizedBox(
                      width: _markRoom,
                      height: _markRoom,
                      child: Center(
                        child: hover && !phone && live && daemon != null
                            ? stopButton(
                                context,
                                daemon!,
                                chat,
                                call.id,
                                size: 13,
                              )
                            : TaskMark(w.state),
                      ),
                    ),
                    if (!phone)
                      Icon(
                        Icons.chevron_right,
                        size: 15,
                        color: t.textSecondary,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The room of a card's mark, its Stop's size: Stop's 13 and its padding.
const double _markRoom = 13 + 5 * 2;

/// "Workflow: review-changes", the kind in bold and the subagents'
/// accent, on one line: the card's and its pane's head, as [subagentName]
/// for a subagent.
Widget workflowName(BuildContext context, Item call, {double size = 13}) {
  final theme = NushiTheme.of(context);
  final t = theme.t;
  final w = call.workflow;
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: 'Workflow: ',
          style: theme.ui(
            t.subagentAccent,
            size: size,
            weight: FontWeight.w600,
          ),
        ),
        TextSpan(
          text: w.name.isNotEmpty ? w.name : w.runId,
          style: theme.ui(t.text, size: size),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

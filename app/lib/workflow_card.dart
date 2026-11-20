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
/// subagents' soft tint, as a subagent's, no outline, of three lines: its
/// name and its state at the end, live ("Review 5/7 · 3 running · 4m
/// 12s"); its description; its phases and who runs. Narrow, the state
/// takes the second line and the phases' line goes. A click opens its pane
/// (the accent's soft fill while open; the failures' soft red once it
/// failed); under the pointer, a running one's mark becomes its Stop. On
/// the phone ([Daemon.remote]) it opens nothing and has no Stop: the chat's
/// sheet stops it.
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

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final w = call.workflow;
    final phone = daemon?.remote ?? false;
    final failed = w.state == 'failed';
    final live = workflowLive(w);
    final muted = theme.ui(t.textMuted, size: 12);
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
          padding: const EdgeInsets.fromLTRB(
            Collapsible.side,
            8,
            Collapsible.side,
            8,
          ),
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 2,
                children: [
                  SizedBox(
                    height: 20,
                    child: Row(
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
                        // The name takes the room; the state ends the line,
                        // half of it at most. Where the row is narrow (a
                        // phone's) the state has a line of its own.
                        if (!narrow)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: math.min(320, box.maxWidth / 2),
                            ),
                            child: state,
                          ),
                        if (hover && !phone && live && daemon != null)
                          stopButton(context, daemon!, chat, call.id, size: 13)
                        else
                          TaskMark(w.state),
                        if (!phone)
                          Icon(
                            Icons.chevron_right,
                            size: 15,
                            color: t.textSecondary,
                          ),
                      ],
                    ),
                  ),
                  if (narrow)
                    Padding(
                      padding: const EdgeInsets.only(left: 15 + 8),
                      child: state,
                    ),
                  if (w.description.isNotEmpty) _line(w.description, muted),
                  // Narrow, the state says the phase it's in: the line of
                  // phases would only be cut.
                  if (!narrow && (w.phases.isNotEmpty || w.running.isNotEmpty))
                    _line(
                      [
                        if (w.phases.isNotEmpty) phasesLine(w),
                        if (live && w.running.isNotEmpty) w.running.join(', '),
                      ].join('  ·  '),
                      theme.ui(t.textSecondary, size: 12),
                      // Long labels are cut, never how many more run.
                      more: live && runningMore(w) > 0
                          ? '+${runningMore(w)}'
                          : null,
                    ),
                  if (ended.isNotEmpty)
                    _line(
                      ended,
                      muted.copyWith(color: failed ? t.crashed : null),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// One line, cut at its end, then [more] whole; its indent lines up
  /// with the name's.
  Widget _line(String text, TextStyle style, {String? more}) => Padding(
    padding: const EdgeInsets.only(left: 15 + 8),
    child: Row(
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (more != null) Text(' $more', maxLines: 1, style: style),
      ],
    ),
  );
}

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

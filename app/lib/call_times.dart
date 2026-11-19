import 'package:flutter/widgets.dart';

import 'package:nushi/clock.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/live_text.dart';
import 'package:nushi/status.dart';
import 'package:nushi/theme/theme.dart';

/// Whether a tool call's time runs: it runs, and no end (its own, or its
/// turn's) stopped it.
bool callTicking(Item it) =>
    (it.status == 'pending' || it.status == 'in_progress') &&
    it.started != 0 &&
    it.ended == 0;

/// How long a tool call ran, or has run so far; null when the daemon
/// didn't see it start or end (a replayed call), or it took under a
/// second.
Duration? callTime(Item it) => runTime([it]);

/// How long a run of tool calls took, from the first's start to the last's
/// end, or to now while one still runs; null as [callTime].
Duration? runTime(List<Item> calls) {
  DateTime? from;
  DateTime? to;
  for (final c in calls) {
    final start = msTime(c.started.toInt());
    if (start == null) continue;
    if (from == null || start.isBefore(from)) from = start;
    final end = callTicking(c) ? clock() : msTime(c.ended.toInt());
    if (end != null && (to == null || end.isAfter(to))) to = end;
  }
  if (from == null || to == null) return null;
  final took = to.difference(from);
  return took < const Duration(seconds: 1) ? null : took;
}

/// The room a time takes at a row's end, with the gap before it: "12m 04s"
/// in 12-point tabular figures. A row with less after its title shows
/// none rather than push its title into an ellipsis past its least.
const double callTimeRoom = 60;

/// A tool call's or a run's time at its row's end ([runTime] of [calls]):
/// muted, secondary, ticking while one of them runs; nothing when it isn't
/// known or took under a second.
class CallTime extends StatelessWidget {
  const new(this.calls, {super.key});

  final List<Item> calls;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final ticking = calls.any(callTicking);
    if (!ticking && runTime(calls) == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: LiveText(
        () => switch (runTime(calls)) {
          final d? => elapsed(d),
          null => '',
        },
        live: ticking,
        style: theme.ui(theme.t.textMuted, size: 12),
      ),
    );
  }
}

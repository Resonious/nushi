import 'dart:math' as math;

import 'package:nushi/clock.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/status.dart';

// A workflow: a run a tool call launched (Claude's Workflow), many
// subagents in phases, followed by the daemon from the agent's files
// (ADR 0127). Item.workflow is its summary; GetWorkflow its agents.

/// Whether [it] launched a workflow the daemon follows: it shows as a
/// workflow's card. One it doesn't (no files found, an older daemon) is a
/// plain call.
bool isWorkflow(Item it) =>
    it.kind == ItemKind.ITEM_KIND_TOOL_CALL &&
    it.hasWorkflow() &&
    it.workflow.state.isNotEmpty;

/// The workflows among [items], in order.
List<Item> workflowsOf(List<Item> items) => items.where(isWorkflow).toList();

/// Whether the workflow runs, stalled or not: it can be stopped.
bool workflowLive(Workflow w) => w.state == 'running';

/// How long it ran, or runs: from its start to its end, or to now.
String workflowTime(Workflow w) {
  final since = msTime(w.started.toInt());
  final end = workflowLive(w) ? clock() : msTime(w.ended.toInt());
  return since == null || end == null ? '' : elapsed(end.difference(since));
}

/// The phase it's in now: the last one reached that hasn't ended, else
/// the last; null when it has none.
WorkflowPhase? currentPhase(Workflow w) {
  for (final p in w.phases.reversed) {
    if (p.done + p.failed < p.started) return p;
  }
  return w.phases.isEmpty ? null : w.phases.last;
}

/// A phase's progress: "Review 5/7" (its agents ended of those started).
String phaseProgress(WorkflowPhase p) =>
    '${p.title} ${p.done + p.failed}/${p.started}';

/// Its state line: while it runs "Review 5/7 · 3 running · 4m 12s"; at its
/// end "done · 100 agents · 14m 05s" ("failed", "stopped", "ended" when the
/// agent didn't say how); stalled "no activity for 1h · Review 5/7 · 3
/// running", without its time, which no longer ticks and would be cut
/// first where the line is short (a phone's).
String workflowState(Workflow w) {
  final time = workflowTime(w);
  final agents = '${w.agents} agent${w.agents == 1 ? '' : 's'}';
  if (workflowLive(w)) {
    final phase = currentPhase(w);
    return [
      if (w.stalled) 'no activity for ${_quiet(w)}',
      if (phase != null) phaseProgress(phase),
      if (w.runningCount > 0) '${w.runningCount} running',
      if (phase == null && w.runningCount == 0) 'starting',
      if (time.isNotEmpty && !w.stalled) time,
    ].join(' · ');
  }
  return [
    switch (w.state) {
      'done' => 'done',
      'failed' => 'failed',
      'stopped' => 'stopped',
      _ => 'ended',
    },
    if (w.agents > 0) agents,
    if (time.isNotEmpty) time,
  ].join(' · ');
}

/// How long its files have been still, roughly: "1h", "2h".
String _quiet(Workflow w) {
  final active = msTime(w.active.toInt());
  if (active == null) return '1h';
  final h = clock().difference(active).inHours;
  return '${h < 1 ? 1 : h}h';
}

/// Its phases on one line, each with its progress: "Map 2/2 · Review 5/7".
String phasesLine(Workflow w) => w.phases.map(phaseProgress).join(' · ');

/// How many run beyond the labels the summary holds: the "+1" after
/// "review:security, review:ui".
int runningMore(Workflow w) => math.max(0, w.runningCount - w.running.length);

/// What it says when it ended otherwise than done: Claude's own word, or
/// the reason a failed run gave.
String workflowEndWords(Workflow w) => switch (w.state) {
  'unknown' => w.end.isEmpty ? "Claude didn't say how it ended" : w.end,
  'failed' when w.summary.isNotEmpty => w.summary,
  'stopped' when w.end.isNotEmpty && w.end != 'killed' => w.end,
  _ => '',
};

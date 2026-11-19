import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/message_actions.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/pond.dart';
import 'package:nushi/subagents.dart';
import 'package:nushi/workflows.dart';

// The transcript's entries: its items grouped into runs and subagents,
// their keys and the room above each, and a message on its way.

/// Whether [e] is a tool call that shows as a row, and can join a run of
/// them (a review's findings and a workflow show as cards of their own).
bool _row(Object? e) =>
    e is Item &&
    e.kind == ItemKind.ITEM_KIND_TOOL_CALL &&
    !e.hasFindings() &&
    !isWorkflow(e);

/// The items, with each run of tool calls as one list, and each subagent
/// as one [SubagentRun] with what it did.
List<Object> transcriptEntries(List<Item> items) {
  final subs = {for (final s in subagentsOf(items)) s.call.id: s};
  final out = <Object>[];
  for (final it in items) {
    final last = out.lastOrNull;
    if (subs.containsKey(it.parent)) continue;
    if (subs[it.id] case final sub?) {
      out.add(sub);
    } else if (_row(it) && last is List<Item>) {
      last.add(it);
    } else if (_row(it) && _row(last)) {
      out.last = [last! as Item, it];
    } else {
      out.add(it);
    }
  }
  return out;
}

/// An entry's items: a run's calls, a subagent's call and steps, or one.
List<Item> entryItems(Object e) => switch (e) {
  final List<Item> run => run,
  final SubagentRun s => [s.call, ...s.items],
  _ => [e as Item],
};

/// An entry's key: a call and the group it becomes keep their place (and
/// state).
String entryKey(Object e) => switch (e) {
  final List<Item> run => run.first.id,
  final SubagentRun s => 'agent ${s.call.id}',
  _ => (e as Item).id,
};

/// A message of yours: faint while on its way ([state] 1), then whole over
/// [Motion.quick] as the daemon shows it; one whose send failed (2) fades
/// out and folds away over [Motion.exit] (the transcript then drops it).
/// With Reduce Motion it's faint, then whole, and goes at once.
class SendingEntry extends StatefulWidget {
  const new({required this.state, required this.child, super.key});

  final int state;
  final Widget child;

  @override
  State<SendingEntry> createState() => _SendingEntryState();
}

class _SendingEntryState extends State<SendingEntry>
    with SingleTickerProviderStateMixin {
  // The message dipping into the pond as it's dropped: down 5 px and a
  // touch smaller, then bobbing back up.
  late final AnimationController _dip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.state == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ripple(glint: false));
    }
  }

  @override
  void didUpdateWidget(SendingEntry old) {
    super.didUpdateWidget(old);
    if (old.state == 1 && widget.state == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ripple(glint: true));
    }
  }

  void _ripple({required bool glint}) {
    if (!mounted || reduceMotion(context)) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // From the bubble itself, not the row it sits in: the first painted
    // box narrower than the row.
    final at = _bubble(box, box.size.width) ??
        box.localToGlobal(box.size.center(Offset.zero));
    if (glint) {
      Pond.glint(context, at);
    } else {
      Pond.drop(context, at);
      unawaited(_dip.forward(from: 0));
    }
  }

  Offset? _bubble(RenderObject o, double rowWidth) {
    if (o is RenderDecoratedBox &&
        o.hasSize &&
        o.size.width < rowWidth * 0.95 &&
        o.size.height > 12) {
      return o.localToGlobal(o.size.center(Offset.zero));
    }
    Offset? found;
    o.visitChildren((c) => found ??= _bubble(c, rowWidth));
    return found;
  }

  @override
  void dispose() {
    _dip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final still = reduceMotion(context);
    final shown = AnimatedOpacity(
      opacity: state == 1 ? 0.7 : 1,
      duration: still ? Duration.zero : Motion.quick,
      child: AnimatedBuilder(
        animation: _dip,
        builder: (context, child) {
          final v = _dip.value;
          // A damped bob: down, up past rest, settle.
          final y = 3 * math.sin(v * math.pi * 2.2) * math.pow(1 - v, 1.4);
          final s = 1 - 0.015 * math.sin(v * math.pi) * (1 - v);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(s, s, 1)
              ..setTranslationRaw(0, y, 0),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
    if (state != 2 || still) return shown;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: Motion.exit,
      curve: Motion.leave,
      builder: (context, v, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: v,
          child: Opacity(opacity: 0.7 * v, child: child),
        ),
      ),
      child: IgnorePointer(child: shown),
    );
  }
}

/// Whether [e] is a message of yours, which shows as a band.
bool isBand(Object e) => e is Item && e.kind == ItemKind.ITEM_KIND_USER_MESSAGE;

/// A user message's band, the agent starting on its own, or where a
/// reopened chat's history comes from changes.
bool _opens(Object e) =>
    isBand(e) ||
    e is Item &&
        e.kind == ItemKind.ITEM_KIND_NOTICE &&
        const {'own_turn', 'compacted', 'history_differs'}.contains(e.status);

/// The room above entry [i]: more around what opens a chapter than between
/// the agent's steps, so each exchange reads as one.
double entryGap(
  List<Object> entries,
  int i, {
  required bool header,
  required bool phone,
}) {
  final gap = _opens(entries[i])
      ? (i == 0 && !header
            ? 8.0
            : phone
            ? 28.0
            : 32.0)
      : (!phone
            ? 16.0
            : i > 0 && _opens(entries[i - 1])
            ? 18.0
            : 12.0);
  // A message's actions keep their room under it.
  final after = !phone && i > 0 && _hasActions(entries[i - 1]);
  return after ? math.max(0, gap - messageActionsHeight) : gap;
}

bool _hasActions(Object e) =>
    e is Item &&
    (e.kind == ItemKind.ITEM_KIND_USER_MESSAGE ||
        e.kind == ItemKind.ITEM_KIND_AGENT_MESSAGE);

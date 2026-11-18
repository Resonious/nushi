import 'dart:async';

import 'package:diff_view/diff_view.dart';
import 'package:flutter/foundation.dart';

import 'package:nushi/diff_box.dart' show maxDiffLines, offThread;

// A file preview's change marks (ADR 0131): which of its lines the chat's
// branch changed (else, with no branch base, since the last commit), worked
// out in the app from the base's text (GetDiff with a path) and the text it
// shows, so they follow unsaved edits too.

/// What a change mark says of its lines.
enum MarkKind { added, changed, removed }

/// A run of lines that differ from the base (`LineBase`): [count] lines
/// from [first] (from 0) of the text shown, added or changed; or, removed,
/// none, the lines having stood before line [first]. [old] is what the
/// base had there (none for added lines).
@immutable
class LineMark {
  const new(this.kind, this.first, this.count, [this.old = const []]);

  final MarkKind kind;
  final int first;
  final int count;
  final List<String> old;

  @override
  bool operator ==(Object other) =>
      other is LineMark &&
      other.kind == kind &&
      other.first == first &&
      other.count == count &&
      listEquals(other.old, old);

  @override
  int get hashCode => Object.hash(kind, first, count, Object.hashAll(old));

  @override
  String toString() => 'LineMark(${kind.name} $first+$count $old)';
}

String _noBom(String s) => s.startsWith('﻿') ? s.substring(1) : s;

/// [text]'s lines as `TextDiff` splits them: a last line break ends the
/// last line, and a line's CR is not its text.
List<String> textLines(String text) {
  final lines = text.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  String noCr(String l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l;
  return [for (final l in lines) noCr(l)];
}

/// Whether [base] or [shown] has more than [maxDiffLines] lines: they
/// get no marks, as a diff isn't drawn then.
bool tooLongToMark(String base, String shown) =>
    textLines(base).length > maxDiffLines ||
    textLines(shown).length > maxDiffLines;

/// The marks of [shown] against [base], the text before: none when
/// they're the same, line endings and a leading BOM aside, or either has
/// more than [maxDiffLines] lines (as a diff isn't drawn then).
List<LineMark> lineMarks(String base, String shown) {
  final old = _noBom(base);
  final now = _noBom(shown);
  if (old == now) return const [];
  if (tooLongToMark(old, now)) return const [];
  final oldLines = textLines(old);
  final blocks = TextDiff.compute(old, now).document.blocks;
  return [
    for (final b in blocks)
      switch (b.kind) {
        BlockKind.inserted => LineMark(
          MarkKind.added,
          b.neu.start,
          b.neu.end - b.neu.start,
        ),
        BlockKind.modified => LineMark(
          MarkKind.changed,
          b.neu.start,
          b.neu.end - b.neu.start,
          oldLines.sublist(b.old.start, b.old.end),
        ),
        BlockKind.deleted => LineMark(
          MarkKind.removed,
          b.neu.start,
          0,
          oldLines.sublist(b.old.start, b.old.end),
        ),
      },
  ];
}

List<LineMark> _marksOf((String, String) texts) =>
    lineMarks(texts.$1, texts.$2);

/// [lineMarks]: at once, or off the UI thread past [offThread]
/// characters, as a diff's box does.
FutureOr<List<LineMark>> lineMarksSoon(String base, String shown) {
  if (base.length + shown.length < offThread) return lineMarks(base, shown);
  return compute(_marksOf, (base, shown));
}

/// What one line's gutter shows: its [bar] (an added or changed run it's
/// in), and a removed run's mark on its [top] or (the last line, where
/// lines went at the end) its [bottom] edge.
@immutable
class MarkCell {
  const new({this.bar, this.top, this.bottom});

  final LineMark? bar;
  final LineMark? top;
  final LineMark? bottom;

  /// What its card tells, top to bottom.
  List<LineMark> get marks => [?top, ?bar, ?bottom];
}

/// Each of [lines] lines' cell of [marks] (null for a line with none).
List<MarkCell?> markCells(List<LineMark> marks, int lines) {
  final cells = List<MarkCell?>.filled(lines, null);
  if (lines == 0) return cells;
  for (final m in marks) {
    if (m.kind == MarkKind.removed) {
      if (m.first < lines) {
        final c = cells[m.first];
        cells[m.first] = MarkCell(bar: c?.bar, top: m, bottom: c?.bottom);
      } else {
        final c = cells[lines - 1];
        cells[lines - 1] = MarkCell(bar: c?.bar, top: c?.top, bottom: m);
      }
      continue;
    }
    for (var i = m.first; i < m.first + m.count && i < lines; i++) {
      final c = cells[i];
      cells[i] = MarkCell(bar: m, top: c?.top, bottom: c?.bottom);
    }
  }
  return cells;
}

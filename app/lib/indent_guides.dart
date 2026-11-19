import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:nushi/source_spans.dart';
import 'package:nushi/whitespace_marks.dart';
import 'package:re_editor/re_editor.dart';

// Indent guides (the Files pane's ⋯, Claude desktop's and VS Code's): a
// faint line down each indent level's first column, in the source and in
// the editor alike. Only drawn: the text is as it was.

/// The lines a blank line looks through, each way, for the indent it sits
/// in: past that it has none.
const _look = 200;

/// A file's indent: each line's level, and the columns a level is wide.
typedef Indents = ({List<int> levels, int unit});

/// The lines [indents] has read, every pass counted: a test's count that
/// it reads each line a fixed number of times, however long a blank run.
@visibleForTesting
int indentLinesRead = 0;

/// The widths a level of spaces can be: the steps people indent by.
const _units = [2, 3, 4, 8];

/// Each of [lines]' indent level and the file's unit ([Indents]): a line's
/// leading spaces and tabs in columns (a tab to its stop, every [size]),
/// in steps of the unit. A file indenting with tabs (more lines start with
/// one than with spaces) steps a tab's [size]; one with spaces steps what
/// it most often indents by from one line to the next (2, 3, 4 or 8, as
/// VS Code's detectIndentation does), else [size]. A blank line (only
/// spaces and tabs) takes the lesser of the nearest lines' around it with
/// text, within [_look] lines each way (none past the file's start or end,
/// or the look: 0), so a block's guides run on through it. One pass each
/// way.
Indents indents(List<String> lines, int size) {
  final n = lines.length;
  final columns = List<int?>.filled(n, null);
  var tabbed = 0;
  var spaced = 0;
  final steps = <int, int>{};
  var previous = 0;
  for (var i = 0; i < n; i++) {
    indentLinesRead++;
    final line = lines[i];
    var column = 0;
    var at = 0;
    for (; at < line.length; at++) {
      final c = line.codeUnitAt(at);
      if (c == 0x20) {
        column++;
      } else if (c == 0x09) {
        column += tabColumns(column, size);
      } else {
        break;
      }
    }
    if (at == line.length) continue;
    columns[i] = column;
    if (at > 0 && line.codeUnitAt(0) == 0x09) tabbed++;
    if (at > 0 && line.codeUnitAt(0) == 0x20) spaced++;
    if (column > previous) {
      steps.update(column - previous, (k) => k + 1, ifAbsent: () => 1);
    }
    previous = column;
  }
  var unit = size;
  if (spaced >= tabbed) {
    var most = 0;
    for (final u in _units) {
      final k = steps[u] ?? 0;
      if (k > most || k == most && k > 0 && u == size) {
        most = k;
        unit = u;
      }
    }
  }
  final own = <int?>[
    for (final c in columns)
      if (c == null) null else c ~/ unit,
  ];
  final before = List<int>.filled(n, 0);
  var last = -1;
  for (var i = 0; i < n; i++) {
    indentLinesRead++;
    if (own[i] != null) {
      last = i;
    } else if (last >= 0 && i - last <= _look) {
      before[i] = own[last]!;
    }
  }
  final levels = List<int>.filled(n, 0);
  var next = -1;
  for (var i = n - 1; i >= 0; i--) {
    indentLinesRead++;
    if (own[i] case final level?) {
      next = i;
      levels[i] = level;
    } else if (next >= 0 && next - i <= _look) {
      levels[i] = min(before[i], own[next]!);
    }
  }
  return (levels: levels, unit: unit);
}

/// The guides' x, from a line's start: each level's first column, [step]
/// (a level's columns' width) apart, [level] of them.
Iterable<double> guidesAt(int level, double step) sync* {
  for (var k = 0; k < level; k++) {
    yield k * step;
  }
}

/// Paints [level] guides down [height] from [at], a line's text's start.
void paintGuides(
  Canvas canvas,
  Offset at,
  int level,
  double step,
  double height,
  Color color,
) {
  if (level <= 0) return;
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1;
  for (final x in guidesAt(level, step)) {
    // On a whole pixel, so it's one sharp line; the one past the line's
    // start, so a gutter laid over the start doesn't cover it.
    final dx = (at.dx + x).ceilToDouble() + 0.5;
    canvas.drawLine(Offset(dx, at.dy), Offset(dx, at.dy + height), paint);
  }
}

/// A line of the read-only source with its indent guides down its height
/// (wrapped, down its first row only: the rows after it start at its
/// first column): [level] of them, [step] apart, from where its child's
/// paragraph (wherever below) starts.
class IndentGuides extends SingleChildRenderObjectWidget {
  const new({
    required this.level,
    required this.step,
    required this.color,
    super.key,
    super.child,
  });

  final int level;
  final double step;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGuides(level, step, color);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderGuides)
        ..level = level
        ..step = step
        ..color = color;
}

class _RenderGuides extends RenderProxyBox {
  new(this._level, this._step, this._color);

  int _level;
  double _step;
  Color _color;

  int get level => _level;
  set level(int v) {
    if (_level == v) return;
    _level = v;
    markNeedsPaint();
  }

  double get step => _step;
  set step(double v) {
    if (_step == v) return;
    _step = v;
    markNeedsPaint();
  }

  Color get color => _color;
  set color(Color v) {
    if (_color == v) return;
    _color = v;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Under the text and its selection: a guide is the faintest thing.
    if (_level > 0) {
      final p = paragraphIn(child);
      if (p != null && p.hasSize) {
        final at = MatrixUtils.transformPoint(
          p.getTransformTo(this),
          Offset.zero,
        );
        // Wrapped, its next rows start at its first column, under the
        // guides: they stop at its first row's foot (VS Code's, wrapping
        // with no indent).
        final row = p.getFullHeightForCaret(const TextPosition(offset: 0));
        final wrapped = p.size.height > row + 0.5;
        paintGuides(
          context.canvas,
          offset + Offset(at.dx, 0),
          _level,
          _step,
          wrapped ? at.dy + row : size.height,
          _color,
        );
      }
    }
    super.paint(context, offset);
  }
}

/// The editor's indent guides over it, where re_editor laid its lines out
/// ([lines]), as [WhitespaceOverlay]'s marks: its text area starts at the
/// right edge of [gutter]; the lines' text is [controller]'s, each level
/// its unit's columns ([indents]) of [column] wide. Only drawn: clicks go
/// through to the editor.
class IndentGuideOverlay extends StatefulWidget {
  const new({
    required this.lines,
    required this.controller,
    required this.gutter,
    required this.column,
    required this.size,
    required this.color,
    super.key,
  });

  final EditorLines lines;
  final CodeLineEditingController controller;
  final GlobalKey gutter;

  /// A column's width.
  final double column;

  /// The tab size the levels are counted in.
  final int size;
  final Color color;

  @override
  State<IndentGuideOverlay> createState() => _IndentGuideOverlayState();
}

class _IndentGuideOverlayState extends State<IndentGuideOverlay> {
  final GlobalKey _area = GlobalKey();

  /// The indents as last counted, for the lines and the tab size they were
  /// counted from: a scroll repaints without counting again.
  (CodeLines, int, Indents)? _counted;

  Indents _indents() {
    final code = widget.controller.codeLines;
    if (_counted case (final c, final s, final counted)
        when identical(c, code) && s == widget.size) {
      return counted;
    }
    final counted = indents([
      for (var i = 0; i < code.length; i++) code[i].text,
    ], widget.size);
    _counted = (code, widget.size, counted);
    return counted;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      key: _area,
      size: Size.infinite,
      painter: _EditorGuides(
        lines: widget.lines,
        controller: widget.controller,
        gutter: widget.gutter,
        area: _area,
        column: widget.column,
        size: widget.size,
        color: widget.color,
        indents: _indents,
      ),
    ),
  );
}

class _EditorGuides extends CustomPainter {
  new({
    required this.lines,
    required this.controller,
    required this.gutter,
    required this.area,
    required this.column,
    required this.size,
    required this.color,
    required this.indents,
  }) : super(repaint: Listenable.merge([lines, controller]));

  final EditorLines lines;
  final CodeLineEditingController controller;
  final GlobalKey gutter;
  final GlobalKey area;
  final double column;
  final int size;
  final Color color;

  /// Each line's level and their unit, counted once for the lines as they
  /// are.
  final Indents Function() indents;

  @override
  void paint(Canvas canvas, Size box) {
    final laidOut = lines.value;
    final g = gutter.currentContext?.findRenderObject();
    final me = area.currentContext?.findRenderObject();
    if (laidOut == null || g is! RenderBox || me is! RenderBox) return;
    if (!g.hasSize) return;
    final origin = MatrixUtils.transformPoint(
      g.getTransformTo(me),
      Offset(g.size.width, 0),
    );
    final clip = Rect.fromLTRB(origin.dx, origin.dy, box.width, box.height);
    if (clip.isEmpty) return;
    final (:levels, :unit) = indents();
    final step = unit * column;
    canvas
      ..save()
      ..clipRect(clip);
    for (final p in laidOut.paragraphs) {
      if (p.index >= levels.length) continue;
      final at = origin + p.offset + Offset(lines.moved, 0);
      // Down its first row: wrapped, the rows after start at column 0.
      paintGuides(
        canvas,
        at,
        levels[p.index],
        step,
        p.preferredLineHeight,
        color,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EditorGuides old) =>
      old.color != color ||
      old.column != column ||
      old.size != size ||
      !identical(old.lines, lines) ||
      !identical(old.controller, controller);
}

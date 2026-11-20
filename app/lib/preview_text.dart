import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:nushi/preview_find.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/transcript_find.dart';

/// [text] indented two spaces a level, when it is JSON; else as it is.
String prettyJson(String text) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
  } on FormatException {
    return text;
  }
}

/// The first [keep] records of [text] read as CSV (RFC 4180: a quoted
/// field holds commas, line breaks and quotes doubled), and how many it has
/// in all.
(List<List<String>>, int) parseCsv(String text, {int keep = 1 << 30}) {
  final rows = <List<String>>[];
  var count = 0;
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var fresh = true; // nothing in the field yet, quotes or not
  void endField() {
    row.add(field.toString());
    field.clear();
    fresh = true;
  }

  void endRow() {
    endField();
    if (count < keep) rows.add(row);
    count++;
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (quoted) {
      if (c != 0x22) {
        field.writeCharCode(c);
      } else if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x22) {
        field.writeCharCode(0x22);
        i++;
      } else {
        quoted = false;
      }
      continue;
    }
    switch (c) {
      case 0x22 when fresh:
        quoted = true;
        fresh = false;
      case 0x2C:
        endField();
      case 0x0D when i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A:
        break; // the \n ends it
      case 0x0A || 0x0D:
        endRow();
      default:
        field.writeCharCode(c);
        fresh = false;
    }
  }
  if (!fresh || row.isNotEmpty) endRow();
  return (rows, count);
}

/// A CSV file as a table: its first row the header, then up to
/// [CsvTable.rows] rows (saying so when there are more), each column as
/// wide as its longest cell, up to 40 characters; wider than the pane, it
/// scrolls sideways. Under a [FindSlot] (the Files pane's) ⌘F finds in
/// the cells it shows, the header's too, every row though only those in
/// sight are laid out; a match cut off by its cell's ellipsis tints the
/// cell.
class CsvTable extends StatefulWidget {
  const new(this.text, {super.key, this.padding});

  /// How many rows under the header show.
  static const rows = 500;

  final String text;
  final EdgeInsets? padding;

  @override
  State<CsvTable> createState() => _CsvTableState();
}

/// A match in a table: its row (0 the header), its cell and its
/// characters there.
typedef _CellHit = ({int row, int cell, int start, int end});

class _CsvTableState extends State<CsvTable> with FindInSlot<CsvTable> {
  late (List<List<String>>, int) _csv = _parse();
  (List<List<String>>, int) _parse() =>
      parseCsv(widget.text, keep: CsvTable.rows + 1);

  @override
  void didUpdateWidget(CsvTable old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _csv = _parse();
      // The find looks in the new cells, once this build is done.
      if (find?.query != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _look(_looked);
        });
      }
    }
  }

  final _across = ScrollController();
  final _down = ScrollController();

  /// The find's matches, for the lowered query [_looked]; each cell's, by
  /// its row and cell; the last ask brought into view; whether the table
  /// starts below the bar, for a match in its first rows.
  List<_CellHit> _hits = const [];
  Map<(int, int), List<int>> _byCell = const {};
  String _looked = '';
  int _shownAsk = -1;
  bool _roomAbove = false;

  @override
  void dispose() {
    _across.dispose();
    _down.dispose();
    super.dispose();
  }

  @override
  void findChanged() {
    final f = find!;
    final q = (f.query ?? '').toLowerCase();
    if (f.query == null) _roomAbove = false;
    if (q != _looked) _look(q);
    setState(() {}); // the cells' marks
    _showCurrent();
  }

  void _look(String query) {
    _looked = query;
    final hits = <_CellHit>[];
    final byCell = <(int, int), List<int>>{};
    for (final (r, cells) in _csv.$1.indexed) {
      for (final (c, text) in cells.indexed) {
        for (final (start, end) in hitsIn(text, query)) {
          (byCell[(r, c)] ??= []).add(hits.length);
          hits.add((row: r, cell: c, start: start, end: end));
        }
      }
    }
    _hits = hits;
    _byCell = byCell;
    find?.found([for (final h in hits) '${h.row}:${h.cell}:${h.start}']);
  }

  /// Cell [c] of row [r]'s matches, as its [LineHits] paints them.
  List<LineHit> _cellHits(int r, int c) {
    final at = _byCell[(r, c)];
    final f = find;
    if (at == null || f == null || f.query == null) return const [];
    final now = _hits.isEmpty ? -1 : f.at.clamp(0, _hits.length - 1);
    return [
      for (final n in at)
        (start: _hits[n].start, end: _hits[n].end, now: n == now),
    ];
  }

  void _showCurrent() {
    final f = find;
    if (f == null || f.query == null || f.asked == _shownAsk) return;
    _shownAsk = f.asked;
    if (_hits.isEmpty) return;
    _reveal(_hits[f.at.clamp(0, _hits.length - 1)], 30);
  }

  /// Takes the table to [hit]: the header's sideways only; a row's, once
  /// it's laid out, onto the match ([revealFound]), until then near it.
  void _reveal(_CellHit hit, int tries) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final view = context.findRenderObject();
        if (!mounted || tries == 0 || view is! RenderBox) return;
        RenderParagraph? p;
        if (hit.row == 0) {
          if (_header.currentContext?.findRenderObject() case final h?) {
            p = hitParagraphIn(h, hit.cell);
          }
          if (p != null) p.showOnScreen(rect: _rectOf(p, hit));
          return;
        }
        final s = _sliverOf(_list.currentContext?.findRenderObject());
        if (s == null || s.firstChild == null || !_down.hasClients) return;
        for (var c = s.firstChild; c != null; c = s.childAfter(c)) {
          if (s.indexOf(c) != hit.row - 1) continue;
          p = hitParagraphIn(c, hit.cell);
          if (p == null || !p.hasSize) return;
          final r = revealFound(
            scroll: _down,
            box: p,
            rect: _rectOf(p, hit),
            view: view,
            roomAbove: _roomAbove,
          );
          if (r == Revealed.needsRoom) {
            setState(() => _roomAbove = true);
            _reveal(hit, tries - 1);
          }
          return;
        }
        final first = s.firstChild!;
        final each = first.size.height;
        final pos = _down.position;
        pos.jumpTo(
          ((hit.row - 1) * each - pos.viewportDimension * 0.3).clamp(
            pos.minScrollExtent,
            pos.maxScrollExtent,
          ),
        );
        _reveal(hit, tries - 1);
      });

  static Rect _rectOf(RenderParagraph p, _CellHit hit) {
    final boxes = hitBoxes(p, hit.start, hit.end);
    return boxes.isEmpty
        ? Offset.zero & p.size
        : boxes.reduce((a, b) => a.expandToInclude(b));
  }

  static RenderSliverMultiBoxAdaptor? _sliverOf(RenderObject? root) {
    RenderSliverMultiBoxAdaptor? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderSliverMultiBoxAdaptor) {
        found = o;
      } else {
        o.visitChildren(visit);
      }
    }

    if (root != null) visit(root);
    return found;
  }

  final GlobalKey _header = GlobalKey();
  final GlobalKey _list = GlobalKey();

  @override
  Widget build(BuildContext context) =>
      FindFrame(find: find, child: _table(context));

  Widget _table(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final colors = findColors(t);
    final (rows, total) = _csv;
    if (rows.isEmpty) {
      return Center(
        child: Text('An empty file.', style: theme.ui(t.textSecondary)),
      );
    }
    final style = theme.code(t.text, size: 12);
    final head = style.copyWith(fontWeight: FontWeight.w600);
    final columns = rows.map((r) => r.length).reduce(max);
    final zero = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final char = zero.width;
    zero.dispose();
    final widths = [
      for (var c = 0; c < columns; c++)
        rows
                    .map((r) => c < r.length ? r[c].length : 0)
                    .reduce(max)
                    .clamp(3, 40) *
                char +
            // The padding, and a character's slack (the header is bold).
            20 +
            char,
    ];
    final width = widths.fold(0.0, (a, w) => a + w);
    final pad = widget.padding ?? EdgeInsets.zero;
    Widget row(int r, TextStyle style, {Key? key}) {
      final cells = rows[r];
      final header = r == 0;
      return DecoratedBox(
        key: key,
        decoration: BoxDecoration(
          color: header ? t.raised : null,
          border: Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(
          children: [
            for (var c = 0; c < columns; c++)
              SizedBox(
                width: widths[c],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: LineHits(
                    hits: _cellHits(r, c),
                    colors: colors,
                    child: Text(
                      c < cells.length ? cells[c] : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final body = rows.length - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        pad.left,
        pad.top + (_roomAbove ? FindBar.height : 0),
        pad.right,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (total - 1 > body)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'The first $body rows of ${total - 1}.',
                style: theme.ui(t.textMuted, size: 12),
              ),
            ),
          Expanded(
            child: Scrollbar(
              controller: _across,
              child: SingleChildScrollView(
                controller: _across,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        row(0, head, key: _header),
                        Expanded(
                          child: ListView.builder(
                            key: _list,
                            controller: _down,
                            padding: EdgeInsets.only(bottom: pad.bottom),
                            itemCount: body,
                            itemBuilder: (context, i) => row(i + 1, style),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

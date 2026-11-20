part of 'source_view.dart';

// ⌘F in a read-only source (issue 63): the file's lines are all there,
// though only those in sight are laid out, so matches are found in the
// text and counted whole; each line paints its own ([LineHits]), and a
// step jumps near the line until it's laid out, then onto the match.

/// A match: its line (from 0) and its characters there.
typedef _Hit = ({int line, int start, int end});

extension on _SourceViewState {
  /// Finds the query in the lines anew and tells the bar.
  void _look(String query) {
    _looked = query;
    final hits = <_Hit>[];
    final byLine = <int, List<int>>{};
    for (final (i, whole) in _lines.indexed) {
      final line = whole.length > _maxLine
          ? whole.substring(0, _maxLine)
          : whole;
      for (final (start, end) in hitsIn(line, query)) {
        (byLine[i] ??= []).add(hits.length);
        hits.add((line: i, start: start, end: end));
      }
    }
    _hits = hits;
    _hitsByLine = byLine;
    find?.found([for (final h in hits) '${h.line}:${h.start}']);
  }

  /// Line [i]'s matches as its [LineHits] paints them.
  List<LineHit> _lineHits(int i) {
    final at = _hitsByLine[i];
    final f = find;
    if (at == null || f == null || f.query == null) return const [];
    final now = _hits.isEmpty ? -1 : f.at.clamp(0, _hits.length - 1);
    return [
      for (final n in at)
        (start: _hits[n].start, end: _hits[n].end, now: n == now),
    ];
  }

  /// Brings the current match into view when it was asked for.
  void _showCurrent() {
    final f = find;
    if (f == null || f.query == null || f.asked == _shownAsk) return;
    _shownAsk = f.asked;
    if (_hits.isEmpty) return;
    _revealHit(_hits[f.at.clamp(0, _hits.length - 1)], 30);
  }

  /// Takes the list to [hit]: once its line is laid out, onto the match
  /// ([revealFound]); until then, near where the line should be, from the
  /// lines laid out, and again after the frame, [tries] times at most.
  void _revealHit(_Hit hit, int tries) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final s = _sliver(wrapped: widget.wrap);
        final view = context.findRenderObject();
        if (!mounted || !_down.hasClients || tries == 0) return;
        if (s == null || s.firstChild == null || view is! RenderBox) return;
        for (var c = s.firstChild; c != null; c = s.childAfter(c)) {
          if (s.indexOf(c) != hit.line) continue;
          final p = hitParagraphIn(c);
          if (p == null || !p.hasSize) return;
          final boxes = hitBoxes(p, hit.start, hit.end);
          final rect = boxes.isEmpty
              ? Offset.zero & p.size
              : boxes.reduce((a, b) => a.expandToInclude(b));
          // Clear of the line numbers, which stay over a run-on line.
          final r = revealFound(
            scroll: _down,
            box: p,
            rect: widget.wrap
                ? rect
                : Rect.fromLTRB(
                    rect.left - _numbers,
                    rect.top,
                    rect.right,
                    rect.bottom,
                  ),
            view: view,
            roomAbove: _roomAbove,
          );
          if (r == Revealed.needsRoom) {
            _setRoomAbove();
            _revealHit(hit, tries - 1);
          }
          return;
        }
        // Not laid out: near it, by the lines that are.
        final first = s.firstChild!;
        final last = s.lastChild!;
        final from = s.childScrollOffset(first)!;
        final to = s.childScrollOffset(last)! + last.size.height;
        final count = s.indexOf(last) - s.indexOf(first) + 1;
        final each = (to - from) / count;
        final p = _down.position;
        p.jumpTo(
          (_top + hit.line * each - p.viewportDimension * 0.3).clamp(
            p.minScrollExtent,
            p.maxScrollExtent,
          ),
        );
        _revealHit(hit, tries - 1);
      });
}

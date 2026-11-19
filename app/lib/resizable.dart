import 'dart:math';

import 'package:flutter/material.dart';

import 'package:nushi/settings.dart';
import 'package:nushi/theme/theme.dart';

/// A pane of a remembered width, with a draggable edge on its [left] or
/// right side: a thin line that highlights under the pointer. Dragging it
/// resizes the pane between [min] and [max]; a double-click resets it to
/// [initial]. The width is remembered across launches by [name]. With
/// [top], the edge is on top and it is the pane's height. The edge lies over
/// the pane's side; a platform view there keeps clear of it ([ClearOfEdge]).
/// While [locked] it has no edge, and takes the width it's made to (an
/// expanded pane, over the view beside it).
class Resizable extends StatefulWidget {
  const new({
    required this.name,
    required this.initial,
    required this.min,
    required this.max,
    required this.child,
    super.key,
    this.left = false,
    this.top = false,
    this.locked = false,
    this.line = true,
    this.onDrag,
  });

  final String name;
  final double initial;
  final double min;
  final double max; // below [min] when there's no room: [min] wins
  final bool left;
  final bool top;
  final bool locked;

  /// Whether the edge shows as a hairline at rest: a divider inside a pane
  /// (a side pane's, the terminal's). Off for the sidebar, which sits on
  /// the window with a gap beside it: its edge shows only under the pointer.
  final bool line;
  final Widget child;

  /// Told the width a drag gives it, in whole points, each time that
  /// changes, and null once the drag ends (and the width is saved): what
  /// lays out beside it can decide on the width as dragged (ADR 0123).
  final ValueChanged<double?>? onDrag;

  /// How far in from the pane's side the edge takes the pointer.
  static const edgeWidth = 5.0;

  @override
  State<Resizable> createState() => _ResizableState();
}

/// [child], a platform view (a WKWebView), kept clear of the edge of the
/// [Resizable] it's in, so the edge lies beside it, not over it. On the Mac
/// a platform view takes the pointer from the Flutter content over it except
/// where that content paints (the engine's hit-test ignore region, from what
/// each frame draws over it): over a web view only the edge's line would
/// start a drag, its unpainted rest giving the press to WebKit. A drag
/// started beside the view goes on over it: AppKit sends the drag and the
/// release to the view that took the press.
class ClearOfEdge extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding:
        context.dependOnInheritedWidgetOfExactType<_Edge>()?.inset ??
        EdgeInsets.zero,
    child: child,
  );
}

/// Where the edge of the [Resizable] around lies, for [ClearOfEdge].
class _Edge extends InheritedWidget {
  const new({required this.inset, required super.child});

  final EdgeInsets inset;

  @override
  bool updateShouldNotify(_Edge old) => inset != old.inset;
}

/// The width the pane [name] was given, or [initial].
double paneWidth(String name, double initial) =>
    paneWidths.value[name] ?? initial;

class _ResizableState extends State<Resizable> {
  double? _asked; // where the pointer has taken the edge
  double? _dragged; // the width the drag asks for, not yet clamped
  double? _told; // the width [Resizable.onDrag] was last told
  double? _from; // the width the drag started at
  bool _hover = false;

  double _width() => (_dragged ?? paneWidth(widget.name, widget.initial)).clamp(
    widget.min,
    max(widget.min, widget.max),
  );

  void _start() => setState(() => _from = _asked = _dragged = _width());

  // A drag's width is a whole number of points, and moves once the pointer
  // is a point from it: a pointer's sub-pixel jitter doesn't change it.
  void _drag(double by) {
    final asked = _asked = _asked! + by;
    if ((asked - _dragged!).abs() < 1) return;
    setState(() => _dragged = asked.roundToDouble());
    final width = _width();
    if (width == _told) return;
    _told = width;
    widget.onDrag?.call(width);
  }

  // Saved in whole points, never past its most: a drag let go at a most
  // that isn't whole (a window of 1209.5) keeps beside what it was beside.
  // One let go where it started saves nothing: a pane narrowed for the
  // room (ADR 0123) keeps the width it was given, pushed at or not.
  void _end() {
    final width = _width();
    final most = max(widget.min, widget.max);
    final whole = width.roundToDouble();
    if (width != _from) _set(whole > most ? most.floorToDouble() : whole);
    setState(() => _from = _asked = _dragged = null);
    if (_told == null) return;
    _told = null;
    widget.onDrag?.call(null);
  }

  @override
  void didUpdateWidget(Resizable old) {
    super.didUpdateWidget(old);
    // Locked mid-drag, its edge is gone and the drag with it.
    if (widget.locked && !old.locked) _asked = _dragged = _told = null;
  }

  void _set(double? width) => paneWidths.value = {
    ...{...paneWidths.value}..remove(widget.name),
    widget.name: ?width,
  };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: paneWidths,
    builder: (context, _, _) {
      final t = NushiTheme.of(context).t;
      final active = _hover || _dragged != null;
      final top = widget.top;
      final edge = MouseRegion(
        cursor: top
            ? SystemMouseCursors.resizeRow
            : SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => _set(null),
          onHorizontalDragStart: top ? null : (_) => _start(),
          onHorizontalDragUpdate: top
              ? null
              : (d) => _drag(widget.left ? -d.delta.dx : d.delta.dx),
          onHorizontalDragEnd: top ? null : (_) => _end(),
          onVerticalDragStart: top ? (_) => _start() : null,
          onVerticalDragUpdate: top ? (d) => _drag(-d.delta.dy) : null,
          onVerticalDragEnd: top ? (_) => _end() : null,
          child: Align(
            alignment: top
                ? Alignment.topCenter
                : widget.left
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Container(
              width: top ? null : (active ? 2 : 1),
              height: top ? (active ? 2 : 1) : null,
              color: active
                  ? t.focus
                  : widget.line
                  ? t.line
                  : null,
            ),
          ),
        ),
      );
      return SizedBox(
        width: top ? null : _width(),
        height: top ? _width() : null,
        child: Stack(
          children: [
            Positioned.fill(
              child: _Edge(
                inset: widget.locked
                    ? EdgeInsets.zero
                    : top
                    ? const EdgeInsets.only(top: Resizable.edgeWidth)
                    : widget.left
                    ? const EdgeInsets.only(left: Resizable.edgeWidth)
                    : const EdgeInsets.only(right: Resizable.edgeWidth),
                child: widget.child,
              ),
            ),
            if (!widget.locked)
              Positioned(
                top: 0,
                bottom: top ? null : 0,
                width: top ? null : Resizable.edgeWidth,
                height: top ? Resizable.edgeWidth : null,
                left: widget.left || top ? 0 : null,
                right: widget.left ? null : 0,
                child: edge,
              ),
          ],
        ),
      );
    },
  );
}

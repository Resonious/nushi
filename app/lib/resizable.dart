import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:nushi/app_log.dart';
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
///
/// A drag runs only while its press is held (ADR 0080, amended 2026-11-19):
/// it starts from a primary press of a mouse, a finger or a stylus, never
/// from a trackpad's two-finger scroll (a pan/zoom, which needs no click
/// and whose end can be lost) or another button; and it ends, its width
/// kept, at the first sign its press was let go unseen (a move without the
/// primary button, a hover of its pointer, the app losing the focus). It
/// ends too, its width dropped, when the edge goes (locked, or the pane
/// closed or rebuilt mid-drag); [onDrag] hears null once whichever way.
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

  /// What may drag an edge: not a trackpad's pan/zoom.
  static const Set<PointerDeviceKind> devices = {
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

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

class _ResizableState extends State<Resizable> with WidgetsBindingObserver {
  double? _asked; // where the pointer has taken the edge
  double? _dragged; // the width the drag asks for, not yet clamped
  double? _told; // the width [Resizable.onDrag] was last told
  double? _from; // the width the drag started at
  bool _hover = false;

  /// The device of the last press on the edge, and of the one dragging it
  /// while one does.
  int? _pressed;
  int? _device;

  // The edge's own recognizers, not a GestureDetector's: a drag cut short
  // has them made anew, so the press they track is dropped with them.
  late DragGestureRecognizer _drag = _newDrag();
  late DoubleTapGestureRecognizer _reset = _newReset();

  DragGestureRecognizer _newDrag() =>
      (widget.top
            ? VerticalDragGestureRecognizer(
                debugOwner: this,
                supportedDevices: Resizable.devices,
              )
            : HorizontalDragGestureRecognizer(
                debugOwner: this,
                supportedDevices: Resizable.devices,
              ))
        ..onStart = ((_) => _start())
        ..onUpdate = ((d) => _move(
          widget.top
              ? -d.delta.dy
              : widget.left
              ? -d.delta.dx
              : d.delta.dx,
        ))
        ..onEnd = ((_) => _finish(save: true))
        ..onCancel = (() => _finish(save: true));

  DoubleTapGestureRecognizer _newReset() => DoubleTapGestureRecognizer(
    debugOwner: this,
    supportedDevices: Resizable.devices,
  )..onDoubleTap = (() => _set(null));

  double _width() => (_dragged ?? paneWidth(widget.name, widget.initial)).clamp(
    widget.min,
    max(widget.min, widget.max),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// A press on the edge: only a primary one of what may drag it.
  void _down(PointerDownEvent e) {
    if (widget.locked ||
        !Resizable.devices.contains(e.kind) ||
        e.buttons != kPrimaryButton) {
      return;
    }
    _pressed = e.device;
    _drag.addPointer(e);
    _reset.addPointer(e);
  }

  void _start() {
    _device = _pressed;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_watch);
    setState(() => _from = _asked = _dragged = _width());
  }

  // A drag's width is a whole number of points, and moves once the pointer
  // is a point from it: a pointer's sub-pixel jitter doesn't change it.
  void _move(double by) {
    final was = _asked;
    if (was == null) return; // cut short: its press is no longer heard
    final asked = _asked = was + by;
    if ((asked - _dragged!).abs() < 1) return;
    setState(() => _dragged = asked.roundToDouble());
    final width = _width();
    if (width == _told) return;
    _told = width;
    widget.onDrag?.call(width);
  }

  /// The dragging press moved: without the primary button it was let go,
  /// though no release came (the engine sent a move for the next button,
  /// or for none).
  void _moved(PointerMoveEvent e) {
    if (e.device == _device && e.buttons & kPrimaryButton == 0) {
      _cut('move without its button');
    }
  }

  /// Every pointer event while a drag runs: its pointer hovering, or gone,
  /// means its press was let go, though no release came.
  void _watch(PointerEvent e) {
    if (e.device != _device) return;
    if (e is PointerHoverEvent) _cut('hover');
    if (e is PointerRemovedEvent) _cut('removed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cut('app not active');
  }

  /// Ends the drag here, as if let go, at a sign its press was let go that
  /// the recognizer can't see, and logs which (ADR 0038): the pane's name
  /// and the sign, nothing more. Its recognizers are made anew, so the
  /// press they track can't move the edge again.
  void _cut(String why) {
    if (_from == null) return;
    appLog.warn("a pane's drag ended: its press was let go unseen", {
      'pane': widget.name,
      'check': why,
    });
    _finish(save: true);
    _renew();
  }

  void _renew() {
    final (drag, reset) = (_drag, _reset);
    _drag = _newDrag();
    _reset = _newReset();
    drag.dispose();
    reset.dispose();
  }

  /// The drag's end. [save]: as let go, saved in whole points, never past
  /// its most: a drag let go at a most that isn't whole (a window of
  /// 1209.5) keeps beside what it was beside. One let go where it started
  /// saves nothing: a pane narrowed for the room (ADR 0123) keeps the
  /// width it was given, pushed at or not. Otherwise (the edge gone) it's
  /// dropped. [Resizable.onDrag] hears null once, after the frame when the
  /// tree is being built or torn down ([building]).
  void _finish({required bool save, bool building = false}) {
    if (_from == null) return;
    if (save) {
      final width = _width();
      final most = max(widget.min, widget.max);
      final whole = width.roundToDouble();
      if (width != _from) _set(whole > most ? most.floorToDouble() : whole);
    }
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_watch);
    _device = null;
    _from = _asked = _dragged = null;
    if (!building) setState(() {});
    if (_told == null) return;
    _told = null;
    final tell = widget.onDrag;
    if (tell == null) return;
    if (building) {
      scheduleMicrotask(() => tell(null));
    } else {
      tell(null);
    }
  }

  @override
  void didUpdateWidget(Resizable old) {
    super.didUpdateWidget(old);
    // Locked mid-drag, its edge is gone and the drag with it.
    if (widget.locked && !old.locked) {
      _finish(save: false, building: true);
      _renew();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finish(save: false, building: true);
    _drag.dispose();
    _reset.dispose();
    super.dispose();
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
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _moved,
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

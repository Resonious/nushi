part of 'beside.dart';

/// A pane beside a view, as its [PaneSpec] says, and what it shows.
class SidePane extends PaneSpec {
  /// One of [spec]'s sizes, showing [child].
  new of(PaneSpec spec, {required this.child})
    : fixed = false,
      super(
        spec.name,
        initial: spec.initial,
        min: spec.min,
        cap: spec.cap,
        wide: spec.wide,
        squeezed: spec.squeezed,
      );

  /// A pane of one [width], with no edge to drag: the details panel
  /// (ADR 0092), which shows or hides only.
  new fixed(super.name, {required double width, required this.child})
    : fixed = true,
      super(initial: width, min: width, cap: width);

  final bool fixed;
  final Widget child;

  double get width => fixed ? initial : saved(paneWidths.value);
}

/// What [Beside] tells its [Beside.head].
class _BesideScope extends InheritedWidget {
  const new({
    required this.glide,
    required this.scene,
    required this.held,
    required super.child,
  });

  final Object glide;
  final Object? scene;
  final bool held;

  @override
  bool updateShouldNotify(_BesideScope old) =>
      glide != old.glide || scene != old.scene || held != old.held;
}

enum _Slot { main, head, foot }

/// Lays [Beside]'s parts out as its build decided ([besideFit]), measuring
/// the panes as laid out, so a pane being resized moves the rest with it;
/// it decides nothing itself.
///
/// The panes run its full height at its right, right to left; left of them
/// the header across the view and the rail, the terminal under them, and
/// between the two the view and, at its right, the rail. Over the main
/// view, those keep [block] (the view's least) and lie under the panes,
/// which cover their right: the same parts in the same places, the panes
/// only further left. Those [going] stay where they were ([at], which it
/// keeps up to date), laid out as they were; so does the rail while it's
/// tucked away.
class _Beside extends MultiChildLayoutDelegate with NoticesPlace {
  new({
    required this.panes,
    required this.rail,
    required this.railShown,
    required this.railWidth,
    required this.squeezed,
    required this.going,
    required this.at,
    required this.widths,
    this.block,
    this.cover,
    this.floor,
    this.barsStart = 0,
  });

  final List<String> panes; // left to right
  final String? rail; // the rail's slot, while it's in the tree
  final bool railShown;
  final double railWidth;
  final double? block; // the view's width under the panes, over it
  final Map<String, double> squeezed; // the most each takes, too narrow
  final List<String> going;
  final Map<String, Rect> at;
  final Map<String, double> widths; // each pane's, as last laid out beside
  final String? cover; // the pane over all, the whole of it
  final CardFloor? floor; // what the newer release's card stands above
  final double barsStart; // the bars' left, across the top: past the lights

  @override
  void performLayout(Size size) {
    final width = size.width;
    final head = hasChild(_Slot.head) ? PaneHeader.height : 0.0;
    final bars = hasChild(NoticeSlot.bars);
    double layBars(double across) => layoutChild(
      NoticeSlot.bars,
      BoxConstraints.tightFor(width: max(0, across)),
    ).height;
    // The bars take a row of their own (ADR 0128, amended 2026-11-17),
    // under the header: as wide as it while the panes are beside the view,
    // their own headers level with it; across it all while they lie over
    // the view, and they go down under it, a drawer over the view under
    // the bars. Over a pane that covers it all, across the top, which goes
    // down by their height.
    final atTop = bars && cover != null;
    final lift = atTop ? layBars(width - barsStart) : 0.0;
    if (atTop) positionChild(NoticeSlot.bars, Offset(barsStart, 0));
    final across0 = bars && cover == null && block != null;
    final overRow = across0 ? layBars(width) : 0.0;
    final drop = lift + (overRow > 0 ? head + overRow : 0);
    final height = size.height - lift;
    final paneHeight = size.height - drop;
    double foot(double across) {
      if (!hasChild(_Slot.foot)) return 0;
      final h = layoutChild(
        _Slot.foot,
        BoxConstraints(
          minWidth: across,
          maxWidth: across,
          maxHeight: max(0, height - head),
        ),
      ).height;
      positionChild(_Slot.foot, Offset(0, size.height - h));
      return h;
    }

    void place(String slot, Rect r) {
      layoutChild(slot, BoxConstraints.tight(r.size));
      positionChild(slot, r.topLeft);
    }

    // The panes run the full height, beside the view or over it.
    var x = width;
    for (final p in panes.reversed) {
      if (p == cover) {
        // It fills it all; the rest keep the room they had beside it, so
        // nothing under it is laid out anew.
        place(p, Rect.fromLTWH(0, lift, width, height));
        x -= widths[p] ?? 0;
        continue;
      }
      final w = layoutChild(
        p,
        BoxConstraints(
          maxWidth: squeezed[p] ?? width,
          minHeight: paneHeight,
          maxHeight: paneHeight,
        ),
      ).width;
      widths[p] = w;
      x -= w;
      positionChild(p, Offset(x, drop));
      at[p] = Rect.fromLTWH(x, drop, w, paneHeight);
    }
    // The view's header, terminal and rail: beside the panes, the room
    // they leave; over the view, its least, under them.
    final across = block ?? max(0.0, x);
    final bottom = size.height - foot(across);
    if (head > 0) {
      // Over the bars' row across it all, the panes gone down under it,
      // the header is all there: as wide as the row, its line unbroken.
      final wide = overRow > 0 ? width : across;
      layoutChild(_Slot.head, BoxConstraints.tight(Size(wide, head)));
      positionChild(_Slot.head, Offset(0, lift));
    }
    // Under the header: beside the panes as wide as it, so only the view
    // and the rail go down; over the view, across it all (laid out above).
    final row = !bars || atTop
        ? 0.0
        : across0
        ? overRow
        : layBars(across);
    if (bars && !atTop) positionChild(NoticeSlot.bars, Offset(0, head));
    final top = lift + head + row;
    final band = max(0.0, bottom - top);
    var main = across;
    if (rail case final r?) {
      if (railShown) {
        main = max(0, across - railWidth);
        place(r, at[r] = Rect.fromLTWH(main, top, railWidth, band));
      } else {
        // Going, or tucked away: where it was, as it was.
        place(
          r,
          at[r] ??
              Rect.fromLTWH(max(0, across - railWidth), top, railWidth, band),
        );
      }
    }
    for (final g in going) {
      place(g, at[g] ?? Rect.fromLTWH(width, drop, 0, paneHeight));
    }
    layoutChild(_Slot.main, BoxConstraints.tight(Size(main, band)));
    positionChild(_Slot.main, Offset(0, top));
    // The toasts over the transcript, under the bars, what the rail and
    // the panes leave of it, and the card in the corner (ADR 0128); a bar
    // of the view's is hidden under the panes lying over it.
    floor?.cut = block != null && cover == null ? x : null;
    if (hasChild(NoticeSlot.card)) {
      placeNotices(
        size: size,
        top: top + ToastHost.margin,
        left: 0,
        right: cover != null ? width : min(main, x),
      );
    }
  }

  @override
  bool shouldRelayout(_Beside old) => true; // cheap: a few panes
}

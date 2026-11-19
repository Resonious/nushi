import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:nushi/firefly.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/theme/theme.dart';

/// A long turn's end, celebrated: a koi leaps out of the turn's line,
/// arcs over the window, and dives into the chat's dot in the sidebar,
/// which takes its check as the koi lands. Drawn on the window's overlay,
/// over everything, taking no pointer. Not with Reduce Motion.
abstract final class KoiLeap {
  /// How long the koi is in the air.
  static const flight = Duration(milliseconds: 1250);

  /// The landing's rings after it.
  static const after = Duration(milliseconds: 700);

  /// The sidebar's dots, by chat, for the koi to land in.
  static final dots = <String, BuildContext>{};

  static final _heading = <String, List<VoidCallback>>{};

  static Offset? _mark(RenderObject o) {
    if (o is RenderCustomPaint && o.hasSize && o.size.width > 4) {
      return o.localToGlobal(o.size.center(Offset.zero));
    }
    Offset? found;
    o.visitChildren((c) => found ??= _mark(c));
    return found;
  }

  /// Whether a koi is on its way to [chatId]'s dot.
  static bool heading(String chatId) => _heading.containsKey(chatId);

  /// Calls [then] as the koi heading to [chatId]'s dot lands (at once if
  /// none is).
  static void onLand(String chatId, VoidCallback then) {
    final list = _heading[chatId];
    if (list == null) {
      then();
    } else {
      list.add(then);
    }
  }

  /// A short turn's end: a firefly drifts from the turn's line to the dot.
  static const fireflyFlight = Duration(milliseconds: 950);
  static const fireflyAfter = Duration(milliseconds: 450);

  /// A koi leaps from [from] (its context's left middle) to [chatId]'s dot.
  /// Called as the turn ends: where both are is read after this frame.
  static void leap(BuildContext from, String chatId) =>
      _launch(from, chatId, firefly: false);

  /// A firefly drifts from [from] to [chatId]'s dot: a short turn's end.
  static void firefly(BuildContext from, String chatId) =>
      _launch(from, chatId, firefly: true);

  static void _launch(
    BuildContext from,
    String chatId, {
    required bool firefly,
  }) {
    if (reduceMotion(from)) return;
    _heading[chatId] = [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void landed() {
        for (final f in _heading.remove(chatId) ?? const <VoidCallback>[]) {
          f();
        }
      }

      final box = from.mounted ? from.findRenderObject() as RenderBox? : null;
      final overlay = from.mounted
          ? Overlay.maybeOf(from, rootOverlay: true)
          : null;
      if (box == null || !box.hasSize || overlay == null) {
        landed();
        return;
      }
      // From the line's mark (its check), else its left middle.
      final start = _mark(box) ??
          box.localToGlobal(Offset(14, box.size.height / 2));
      final dot = dots[chatId];
      final dotBox = dot != null && dot.mounted
          ? dot.findRenderObject() as RenderBox?
          : null;
      final end = dotBox != null && dotBox.hasSize
          ? dotBox.localToGlobal(dotBox.size.center(Offset.zero))
          // No sidebar: it dives back in, up the transcript.
          : start + const Offset(-40, -260);
      final t = NushiTheme.of(from).t;
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => _Flight(
          from: start,
          to: end,
          dark: t.brightness == Brightness.dark,
          water: t.shineBand,
          ring: t.done,
          glow: t.gold,
          firefly: firefly,
          onLanded: landed,
          onDone: () => entry.remove(),
        ),
      );
      overlay.insert(entry);
    });
  }
}

class _Flight extends StatefulWidget {
  const _Flight({
    required this.from,
    required this.to,
    required this.dark,
    required this.water,
    required this.ring,
    required this.glow,
    required this.firefly,
    required this.onLanded,
    required this.onDone,
  });

  final Color glow;
  final bool firefly;

  final Offset from;
  final Offset to;
  final bool dark;
  final Color water;
  final Color ring;
  final VoidCallback onLanded;
  final VoidCallback onDone;

  @override
  State<_Flight> createState() => _FlightState();
}

class _FlightState extends State<_Flight> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.firefly
        ? KoiLeap.fireflyFlight + KoiLeap.fireflyAfter
        : KoiLeap.flight + KoiLeap.after,
  );
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    _c
      ..addListener(() {
        if (!_landed &&
            _c.value >=
                (widget.firefly ? FireflyPainter.landAt : _KoiPainter.landAt)) {
          _landed = true;
          widget.onLanded();
        }
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward().ignore();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: widget.firefly
            ? FireflyPainter(
                _c,
                from: widget.from,
                to: widget.to,
                glow: widget.glow,
                ring: widget.ring,
                dark: widget.dark,
              )
            : _KoiPainter(
                _c,
                from: widget.from,
                to: widget.to,
                dark: widget.dark,
                water: widget.water,
                ring: widget.ring,
              ),
      ),
    ),
  );
}

class _KoiPainter extends CustomPainter {
  _KoiPainter(
    this.clock, {
    required this.from,
    required this.to,
    required this.dark,
    required this.water,
    required this.ring,
  }) : super(repaint: clock);

  final Animation<double> clock;
  final Offset from;
  final Offset to;
  final bool dark;
  final Color water;
  final Color ring;

  static final double landAt =
      KoiLeap.flight.inMicroseconds /
      (KoiLeap.flight + KoiLeap.after).inMicroseconds;
  static const _total = 1.95; // seconds, flight and after

  static const _white = Color(0xFFF8F4EC); // design: the koi's own colours
  static const _red = Color(0xFFE2471F);
  static const _redDeep = Color(0xFFB8300F);

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  // The arc: up and out, away from the dot, then turning back over and
  // diving down onto it. Kept inside the window's top.
  double get _away => to.dx < from.dx ? 1 : -1;
  Offset get _p1 =>
      Offset(from.dx + _away * 150, math.max(24, from.dy - 260));
  Offset get _p2 => Offset(to.dx + _away * 120, math.max(16, to.dy - 150));

  Offset _at(double u) {
    final v = 1 - u;
    return from * (v * v * v) +
        _p1 * (3 * v * v * u) +
        _p2 * (3 * v * u * u) +
        to * (u * u * u);
  }

  Offset _heading(double u) {
    final v = 1 - u;
    return (_p1 - from) * (3 * v * v) +
        (_p2 - _p1) * (6 * v * u) +
        (to - _p2) * (3 * u * u);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final secs = clock.value * _total;
    final flight = KoiLeap.flight.inMicroseconds / 1e6;
    final u = (secs / flight).clamp(0.0, 1.0);

    _splash(canvas, from, secs, big: true);
    _trail(canvas, secs, flight);
    if (secs >= flight * 0.97) _splash(canvas, to, secs - flight, big: false);
    if (u < 1) _koi(canvas, u, secs);
  }

  /// Rings and a few drops where the koi leaves the water or enters it.
  void _splash(Canvas canvas, Offset at, double age, {required bool big}) {
    if (age < 0) return;
    final rng = math.Random(big ? 7 : 11);
    final life = big ? 0.8 : 0.7;
    for (var i = 0; i < 3; i++) {
      final a = age - i * 0.12;
      if (a < 0 || a > life) continue;
      final v = a / life;
      final r = (big ? 6 : 4) + (big ? 30 : 20) * Curves.easeOut.transform(v);
      _stroke
        ..strokeWidth = 1.4 * (1 - v) + 0.4
        ..color = (big ? water : ring).withValues(alpha: 0.7 * (1 - v));
      // The water is seen from above at a slant: flattened rings.
      canvas.drawOval(
        Rect.fromCenter(center: at, width: r * 2, height: r * 1.1),
        _stroke,
      );
    }
    // Drops thrown up, falling back.
    for (var i = 0; i < (big ? 9 : 6); i++) {
      final angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * 1.8;
      final speed = (big ? 140 : 90) + rng.nextDouble() * 90;
      final a = age;
      if (a > 0.6) continue;
      final p = at +
          Offset(math.cos(angle), math.sin(angle)) * speed * a +
          Offset(0, 420 * a * a);
      _fill.color = water.withValues(alpha: 0.85 * (1 - a / 0.6));
      canvas.drawCircle(p, 1.8 * (1 - a / 0.6) + 0.6, _fill);
    }
  }

  /// Drops shaken off the koi's tail along the arc, falling as it goes.
  void _trail(Canvas canvas, double secs, double flight) {
    for (var k = 0; k < 16; k++) {
      final born = flight * (0.06 + 0.055 * k);
      final a = secs - born;
      if (a < 0 || a > 0.55 || born > flight * 0.92) continue;
      final u = born / flight;
      final dir = _heading(u);
      final back = dir / dir.distance;
      final p = _at(u) -
          back * 18 +
          Offset((k.isEven ? 1 : -1) * 14 * a, 380 * a * a);
      _fill.color = water.withValues(alpha: 0.75 * (1 - a / 0.55));
      canvas.drawCircle(p, 1.6 * (1 - a / 0.55) + 0.5, _fill);
    }
  }

  void _koi(Canvas canvas, double u, double secs) {
    final at = _at(u);
    final dir = _heading(u);
    final angle = math.atan2(dir.dy, dir.dx);
    // Bigger mid-air (nearer the viewer), small as it dives into the dot.
    final scale = (1 + 0.45 * math.sin(math.pi * u)) *
        (1 - 0.65 * Curves.easeIn.transform(((u - 0.78) / 0.22).clamp(0, 1)));
    final alpha = (u / 0.05).clamp(0.0, 1.0) *
        (1 - ((u - 0.94) / 0.06).clamp(0.0, 1.0));
    const length = 64.0;
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(angle)
      ..scale(scale);
    if (alpha < 1) {
      canvas.saveLayer(
        const Rect.fromLTWH(-80, -50, 160, 100),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }
    _drawKoi(canvas, length, secs);
    if (alpha < 1) canvas.restore();
    canvas.restore();
  }

  /// A koi heading +x, [length] long, its body flexing with [secs].
  void _drawKoi(Canvas canvas, double length, double secs) {
    const n = 14;
    final half = length / 2;
    final spine = <Offset>[];
    final widths = <double>[];
    // From the head (i = 0) to the tail's root (i = n).
    for (var i = 0; i <= n; i++) {
      final f = i / n; // 0 head, 1 tail
      final x = half - f * length * 0.78;
      final wave = length * 0.11 * f * f * math.sin(secs * 16 - f * 3.2);
      spine.add(Offset(x, wave));
      final s = 1.9 * (1 - f) - 1.0; // 0.9 at the head, -1 at the tail
      widths.add(
        length * 0.165 * math.sqrt(math.max(0, 1 - s * s)) * (0.5 + 0.5 * (1 - f)) +
            length * 0.02,
      );
    }
    Offset normal(int i) {
      final a = spine[math.max(0, i - 1)];
      final b = spine[math.min(n, i + 1)];
      final d = a - b;
      return Offset(-d.dy, d.dx) / d.distance;
    }

    final left = [for (var i = 0; i <= n; i++) spine[i] + normal(i) * widths[i]];
    final right = [
      for (var i = 0; i <= n; i++) spine[i] - normal(i) * widths[i],
    ];
    final tail = spine[n];
    final tailDir = (spine[n] - spine[n - 2]) / (spine[n] - spine[n - 2]).distance;
    final tailNormal = Offset(-tailDir.dy, tailDir.dx);
    final fin = length * 0.3;
    final flap = math.sin(secs * 16 - 3.6) * 0.35;

    // The tail fin: two lobes and a notch, translucent.
    final finPath = Path()
      ..moveTo(tail.dx, tail.dy)
      ..quadraticBezierTo(
        (tail + tailDir * fin * 0.5 + tailNormal * fin * (0.25 + flap)).dx,
        (tail + tailDir * fin * 0.5 + tailNormal * fin * (0.25 + flap)).dy,
        (tail + tailDir * fin + tailNormal * fin * (0.55 + flap)).dx,
        (tail + tailDir * fin + tailNormal * fin * (0.55 + flap)).dy,
      )
      ..quadraticBezierTo(
        (tail + tailDir * fin * 0.6 + tailNormal * fin * flap).dx,
        (tail + tailDir * fin * 0.6 + tailNormal * fin * flap).dy,
        (tail + tailDir * fin - tailNormal * fin * (0.55 - flap)).dx,
        (tail + tailDir * fin - tailNormal * fin * (0.55 - flap)).dy,
      )
      ..quadraticBezierTo(
        (tail + tailDir * fin * 0.5 - tailNormal * fin * (0.25 - flap)).dx,
        (tail + tailDir * fin * 0.5 - tailNormal * fin * (0.25 - flap)).dy,
        tail.dx,
        tail.dy,
      );

    // The body: down the left side, round the tail's root, up the right,
    // round the nose.
    final body = Path()..moveTo(left[0].dx, left[0].dy);
    for (var i = 1; i <= n; i++) {
      body.lineTo(left[i].dx, left[i].dy);
    }
    for (var i = n; i >= 0; i--) {
      body.lineTo(right[i].dx, right[i].dy);
    }
    final nose = spine[0] + const Offset(1, 0) * (length * 0.09);
    body
      ..quadraticBezierTo(nose.dx, nose.dy, left[0].dx, left[0].dy)
      ..close();

    // Its shadow, so it lifts off the window.
    canvas.drawShadow(body, const Color(0xFF000000), 5, false);

    // Pectoral fins, sculling.
    final scull = math.sin(secs * 9) * 0.4;
    for (final side in [1.0, -1.0]) {
      final root = spine[4] + normal(4) * widths[4] * side * 0.8;
      final tip = root +
          Offset(-length * 0.16, side * length * (0.16 + 0.05 * scull));
      final p = Path()
        ..moveTo(root.dx, root.dy)
        ..quadraticBezierTo(
          root.dx - length * 0.02,
          root.dy + side * length * 0.14,
          tip.dx,
          tip.dy,
        )
        ..quadraticBezierTo(
          root.dx - length * 0.1,
          root.dy + side * length * 0.03,
          root.dx - length * 0.08,
          root.dy,
        )
        ..close();
      _fill.color = _white.withValues(alpha: 0.7);
      canvas.drawPath(p, _fill);
    }
    _fill.color = _white.withValues(alpha: 0.75);
    canvas.drawPath(finPath, _fill);
    _stroke
      ..strokeWidth = 0.6
      ..color = _red.withValues(alpha: 0.5);
    canvas.drawPath(finPath, _stroke);

    // The body, white, softly shaded along its back.
    _fill.shader = ui.Gradient.linear(
      Offset(0, -length * 0.2),
      Offset(0, length * 0.2),
      [_white, const Color(0xFFE9E2D6)],
    );
    canvas.drawPath(body, _fill);
    _fill.shader = null;

    // Kohaku's red patches, inside the body: soft-edged, uneven blobs.
    canvas
      ..save()
      ..clipPath(body);
    _fill
      ..color = _red
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1);
    void blob(Offset c, double w, double h, [double dy = 0]) =>
        canvas.drawOval(
          Rect.fromCenter(
            center: c + Offset(0, dy * length),
            width: w * length,
            height: h * length,
          ),
          _fill,
        );
    blob(spine[2], 0.2, 0.2, 0.01);
    blob(spine[3] + Offset(-length * 0.02, 0), 0.12, 0.22, -0.02);
    blob(spine[6], 0.26, 0.2, 0.05);
    blob(spine[8], 0.2, 0.26, 0.01);
    blob(spine[7] + Offset(length * 0.03, 0), 0.1, 0.14, -0.08);
    _fill.color = _redDeep.withValues(alpha: 0.85);
    blob(spine[11], 0.14, 0.12, -0.05);
    _fill.maskFilter = null;
    canvas.restore();

    // Eyes.
    _fill.color = const Color(0xFF1B1B1F);
    for (final side in [1.0, -1.0]) {
      canvas.drawCircle(
        spine[1] + normal(1) * widths[1] * side * 0.6,
        length * 0.022,
        _fill,
      );
    }
  }

  @override
  bool shouldRepaint(_KoiPainter old) => false;
}

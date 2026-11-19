import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:nushi/koi.dart';

/// A short turn's end: a firefly lifts off the turn's line and drifts to
/// the chat's dot in a lazy curve, wandering a little and blinking, a
/// short trail of light behind it; it settles into the dot with a small
/// ring. The koi's leap is for long turns ([KoiLeap.leap]).
class FireflyPainter extends CustomPainter {
  FireflyPainter(
    this.clock, {
    required this.from,
    required this.to,
    required this.glow,
    required this.ring,
    required this.dark,
  }) : super(repaint: clock);

  final Animation<double> clock;
  final Offset from;
  final Offset to;
  final Color glow;
  final Color ring;
  final bool dark;

  static final double landAt =
      KoiLeap.fireflyFlight.inMicroseconds /
      (KoiLeap.fireflyFlight + KoiLeap.fireflyAfter).inMicroseconds;

  final _paint = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  // A lazy curve: up off the line, then across to the dot from above.
  Offset _at(double u) {
    final p1 = Offset(from.dx + (to.dx - from.dx) * 0.15, from.dy - 120);
    final p2 = Offset(to.dx + (from.dx - to.dx) * 0.25, to.dy - 70);
    final v = 1 - u;
    final base = from * (v * v * v) +
        p1 * (3 * v * v * u) +
        p2 * (3 * v * u * u) +
        to * (u * u * u);
    // It wanders: a small sideways weave that dies out as it lands.
    final weave = math.sin(u * math.pi) * 9;
    return base +
        Offset(
          math.sin(u * 11) * weave,
          math.cos(u * 8.3) * weave * 0.6,
        );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final total =
        (KoiLeap.fireflyFlight + KoiLeap.fireflyAfter).inMicroseconds / 1e6;
    final secs = clock.value * total;
    final flight = KoiLeap.fireflyFlight.inMicroseconds / 1e6;
    final raw = (secs / flight).clamp(0.0, 1.0);
    final u = Curves.easeInOutSine.transform(raw);

    if (raw < 1) {
      // Its trail: where it was, fading.
      for (var k = 14; k >= 1; k--) {
        final back = Curves.easeInOutSine.transform(
          (raw - k * 0.009).clamp(0.0, 1.0),
        );
        _paint
          ..shader = null
          ..color = glow.withValues(alpha: 0.35 * (1 - k / 15) * _fadeIn(raw));
        canvas.drawCircle(_at(back), 1.9 * (1 - k / 18), _paint);
      }
      final at = _at(u);
      // Blinking, as fireflies do: a slow pulse with a quick flare.
      final blink = 0.7 + 0.3 * math.sin(secs * 14) + 0.2 * math.sin(secs * 5.3);
      final a = _fadeIn(raw) * (raw > 0.9 ? 1 - (raw - 0.9) * 6 : 1).clamp(0.0, 1.0);
      final halo = 24 * blink;
      _paint.shader = ui.Gradient.radial(at, halo, [
        glow.withValues(alpha: (dark ? 0.75 : 0.6) * a),
        glow.withValues(alpha: (dark ? 0.22 : 0.16) * a),
        glow.withValues(alpha: 0),
      ], [0, 0.35, 1]);
      canvas.drawCircle(at, halo, _paint);
      _paint
        ..shader = null
        ..color = Color.lerp(glow, const Color(0xFFFFF6D8), dark ? 0.6 : 0.2)!
            .withValues(alpha: a);
      canvas.drawCircle(at, 3.2, _paint);
    }

    // Settling into the dot: a small ring, from the firefly's gold to the
    // dot's green.
    final after = secs - flight * 0.95;
    if (after > 0) {
      final v = (after / 0.45).clamp(0.0, 1.0);
      final e = Curves.easeOut.transform(v);
      _stroke
        ..strokeWidth = 1.3 * (1 - v) + 0.3
        ..color = Color.lerp(glow, ring, e)!.withValues(alpha: 0.75 * (1 - v));
      canvas.drawCircle(to, 4 + 12 * e, _stroke);
      _paint
        ..shader = ui.Gradient.radial(to, 12, [
          glow.withValues(alpha: 0.5 * (1 - v)),
          glow.withValues(alpha: 0),
        ]);
      canvas.drawCircle(to, 12, _paint);
      _paint.shader = null;
    }
  }

  double _fadeIn(double raw) => (raw / 0.08).clamp(0.0, 1.0);

  @override
  bool shouldRepaint(FireflyPainter old) => false;
}

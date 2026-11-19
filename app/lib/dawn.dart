import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:nushi/motion.dart';
import 'package:nushi/theme/theme.dart';

/// The window as the daemon starts and the app first comes: while it
/// starts ([ready] false), [child] (what says so) over a drop's rings
/// spreading slowly from the middle ([Dawn.rings]); once it's up, one
/// wide ring sweeps out across the window as the app clears and settles
/// behind it, out of a blur. A window that opens on a daemon already up
/// shows the app at once. With Reduce Motion, nothing ripples or rises.
class Dawn extends StatefulWidget {
  const Dawn({required this.ready, required this.child, super.key});

  /// The daemon answered: [child] is the app.
  final bool ready;
  final Widget child;

  /// What the window shows while the daemon starts: [message] under a
  /// drop's slow rings ([still] for a failure: the rings stop).
  static Widget rings(Widget message, {bool still = false}) =>
      _Rings(message: message, still: still);

  @override
  State<Dawn> createState() => _DawnState();
}

class _DawnState extends State<Dawn> with SingleTickerProviderStateMixin {
  late final _come = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );
  // What showed as it waited, kept to fade out over the app.
  Widget? _waiting;

  @override
  void didUpdateWidget(Dawn old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready && !reduceMotion(context)) {
      _waiting = old.child;
      unawaited(
        _come.forward(from: 0).then((_) {
          if (mounted) setState(() => _waiting = null);
        }),
      );
    }
  }

  @override
  void dispose() {
    _come.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Waiting, [child] is what says so; ready, it's the app, always under
    // the same wrappers, still once it's come: a change in the tree's
    // shape would build the whole app again.
    if (!widget.ready) return widget.child;
    final t = NushiTheme.of(context).t;
    final ring = t.brightness == Brightness.dark ? t.shineBand : t.accent;
    return AnimatedBuilder(
      animation: _come,
      builder: (context, app) {
        final waiting = _waiting;
        final v = _come.value;
        // The app: clear from a blur and up into place in the first 70%.
        final a = Curves.easeOutCubic.transform((v / 0.7).clamp(0, 1));
        final sigma = 10 * (1 - a);
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: a,
              child: Transform.scale(
                scale: 0.985 + 0.015 * a,
                child: ImageFiltered(
                  enabled: sigma > 0.05,
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: sigma,
                    sigmaY: sigma,
                    tileMode: TileMode.decal,
                  ),
                  child: app,
                ),
              ),
            ),
            if (waiting != null) ...[
              // What waited, fading as the app comes.
              IgnorePointer(
                child: Opacity(
                  opacity: (1 - v / 0.35).clamp(0.0, 1.0),
                  child: waiting,
                ),
              ),
              // The ring that brings it, out past the window's corners.
              IgnorePointer(
                child: CustomPaint(
                  painter: _Sweep(v, ring),
                  size: Size.infinite,
                ),
              ),
            ],
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// One ring, out from the middle past the window's corners.
class _Sweep extends CustomPainter {
  _Sweep(this.v, this.color);

  final double v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final reach = size.longestSide * 0.75;
    final e = Curves.easeOutCubic.transform(v);
    final fade = (1 - v) * (1 - v);
    if (fade <= 0.002) return;
    final r = 30 + reach * e;
    canvas
      ..drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14 + 30 * e
          ..color = color.withValues(alpha: 0.06 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: 0.35 * fade),
      );
  }

  @override
  bool shouldRepaint(_Sweep old) => old.v != v || old.color != color;
}

/// A drop's rings, slow, from the middle: three at a time, each out and
/// gone over [_period], the drop's glint at their middle breathing.
class _Rings extends StatefulWidget {
  const _Rings({required this.message, required this.still});

  final Widget message;
  final bool still;

  @override
  State<_Rings> createState() => _RingsState();
}

class _RingsState extends State<_Rings> with SingleTickerProviderStateMixin {
  static const _period = 2.6;
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);

  void _tick(Duration now) => _time.value = now.inMicroseconds / 1e6;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(_Rings old) {
    super.didUpdateWidget(old);
    _run();
  }

  void _run() {
    final go = !widget.still && !reduceMotion(context);
    if (go && !_ticker.isActive) unawaited(_ticker.start());
    if (!go && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = NushiTheme.of(context).t;
    final dark = t.brightness == Brightness.dark;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            size: const Size.square(200),
            painter: _RingsPainter(
              _time,
              dark ? t.shineBand : t.accent,
              still: widget.still || reduceMotion(context),
            ),
          ),
        ),
        const SizedBox(height: 4),
        widget.message,
      ],
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.time, this.color, {required this.still})
    : super(repaint: time);

  final ValueNotifier<double> time;
  final Color color;
  final bool still;
  final _paint = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final most = size.shortestSide / 2 - 4;
    const n = 3;
    for (var i = 0; i < n; i++) {
      // Still: the rings as they'd be, held.
      final p = still
          ? (i + 0.5) / n
          : ((time.value / _RingsState._period) + i / n) % 1.0;
      final r = 6 + (most - 6) * Curves.easeOutCubic.transform(p);
      final a = math.pow(1 - p, 1.6) * 0.55;
      _paint
        ..strokeWidth = 1.6 - 0.9 * p
        ..color = color.withValues(alpha: a.toDouble());
      canvas.drawCircle(c, r, _paint);
    }
    // The drop's glint, breathing.
    final b = still ? 0.5 : 0.5 + 0.5 * math.sin(time.value * 2.4);
    canvas
      ..drawCircle(
        c,
        7 + 3 * b,
        Paint()
          ..color = color.withValues(alpha: 0.10 + 0.08 * b)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      )
      ..drawCircle(c, 2.6, Paint()..color = color.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.color != color || old.still != still;
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'package:nushi/motion.dart';
import 'package:nushi/theme/theme.dart';

/// The transcript as a pond's surface: a message dropped in sends a ripple
/// across it ([Pond.drop]) that bends what's under it and catches the
/// light; the daemon's confirmation sends a quick amber glint after it
/// ([Pond.glint]). At rest nothing is snapshotted and nothing ticks: the
/// child paints as it is. With Reduce Motion, nothing ripples.
class Pond extends StatefulWidget {
  const Pond({required this.child, super.key, this.working = false});

  final Widget child;

  /// The agent is working: caustics drift under the live end.
  final bool working;

  /// The shaders, loaded once.
  static ui.FragmentProgram? _program;
  static ui.FragmentProgram? _caustics;
  static Future<void>? _loading;

  /// Loads the shaders; an effect before they're loaded is skipped.
  static Future<void> load() => _loading ??= Future.wait([
    ui.FragmentProgram.fromAsset('shaders/ripple.frag')
        .then((p) => _program = p),
    ui.FragmentProgram.fromAsset('shaders/caustics.frag')
        .then((p) => _caustics = p),
  ]);

  /// Words came in: the light on the floor stirs, brighter for a moment.
  static void stir(BuildContext context) =>
      context.findAncestorStateOfType<_PondState>()?._stir();

  /// A message dropped in at [global] (a point on screen).
  static void drop(BuildContext context, Offset global) =>
      context.findAncestorStateOfType<_PondState>()?._add(global, glint: false);

  /// The list landed at its end, scrolled there by the user at [strength]
  /// (0 to 1, by how fast): a wave runs up from the bottom edge and drops
  /// leap from it. [context] is below the pond (the list's own).
  static void splash(BuildContext context, double strength) =>
      context.findAncestorStateOfType<_PondState>()?._splash(strength);

  /// The daemon has the message at [global]: a glint follows the ripple.
  static void glint(BuildContext context, Offset global) =>
      context.findAncestorStateOfType<_PondState>()?._add(global, glint: true);

  /// A new chat surfaced in the pond somewhere under [context] (above
  /// it): a drop falls where its composer is, its rings running up the
  /// empty transcript. Looks down the tree once.
  static void welcome(BuildContext context) {
    _PondState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is _PondState) {
        found = e.state as _PondState;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    found?._welcome();
  }

  @override
  State<Pond> createState() => _PondState();
}

class _Ripple {
  _Ripple(this.at, {required this.glint, this.edge});

  final Offset at;
  final bool glint;

  /// An edge splash's strength (0 to 1); null for a drop or a glint.
  final double? edge;
  Duration? born;
  double age = 0;

  double get life => edge != null
      ? 1.1
      : glint
      ? 0.9
      : 1.6;

  double get kind => switch (edge) {
    final s? => 2 + 0.9 * s.clamp(0, 1),
    null => glint ? 1 : 0,
  };
}

/// A drop thrown up off the bottom edge by a splash.
class _Drop {
  _Drop(this.x, this.vx, this.vy, this.size);

  final double x;
  final double vx;
  final double vy;
  final double size;
}

class _PondState extends State<Pond> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _snapshot = SnapshotController();
  final _painter = _RipplePainter();
  final _key = GlobalKey();
  // The whole pond (the transcript and what's under it), and what's
  // under it: the caustics run across both as one floor.
  final _area = GlobalKey();
  final _floorKey = GlobalKey();
  late final _caustics = _CausticsPainter(_key, _area);
  late final _floorCaustics = _CausticsPainter(_floorKey, _area);
  final _drops = _DropsPainter();
  Duration? _last;

  // How bright the caustics are: eases toward [_target] (1 while working),
  // plus [_stirred], a burst as words come that settles.
  double _level = 0;
  double _stirred = 0;
  // Only while Nushi is in front (its window focused): a turn can run for
  // minutes, and caustics redraw the pane every frame.
  double get _target =>
      widget.working && appInFront && !reduceMotion(context) ? 1 : 0;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onStateChange: (_) => _run(),
  );

  @override
  void initState() {
    super.initState();
    unawaited(Pond.load());
    _lifecycle; // starts listening
  }

  @override
  void didUpdateWidget(Pond old) {
    super.didUpdateWidget(old);
    if (widget.working != old.working) _run();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  void _run() {
    if (!_ticker.isActive && (_target > 0 || _level > 0)) {
      _last = null;
      unawaited(_ticker.start());
    }
  }

  void _stir() {
    if (_target == 0) return;
    _stirred = (_stirred + 0.25).clamp(0, 0.9);
    _run();
  }

  void _add(Offset global, {required bool glint}) {
    if (Pond._program == null || reduceMotion(context)) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final ripples = _painter.ripples;
    if (ripples.length == 3) ripples.removeAt(0);
    ripples.add(_Ripple(box.globalToLocal(global), glint: glint));
    _snapshot.allowSnapshotting = true;
    if (!_ticker.isActive) unawaited(_ticker.start());
  }

  void _welcome() {
    final floor = _floorKey.currentContext?.findRenderObject() as RenderBox?;
    final box = floor ?? _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    // The composer's middle, or the transcript's foot without one.
    final at = floor != null
        ? size.bottomCenter(Offset.zero) - const Offset(0, 44)
        : size.bottomCenter(Offset.zero);
    _add(box.localToGlobal(at), glint: false);
  }

  void _splash(double strength) {
    if (reduceMotion(context)) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    if (Pond._program != null) {
      final ripples = _painter.ripples;
      if (ripples.length == 3) ripples.removeAt(0);
      ripples.add(
        _Ripple(
          Offset(size.width / 2, size.height),
          glint: false,
          edge: strength,
        ),
      );
      _snapshot.allowSnapshotting = true;
    }
    final rng = math.Random();
    final n = (4 + 7 * strength).round();
    _drops
      ..born = null
      ..age = 0
      ..list = [
        for (var i = 0; i < n; i++)
          _Drop(
            size.width * (0.5 + (rng.nextDouble() - 0.5) * 0.45),
            (rng.nextDouble() - 0.5) * 120,
            -(120 + (140 + 200 * rng.nextDouble()) * strength),
            1.8 + rng.nextDouble() * 1.2,
          ),
      ];
    if (!_ticker.isActive) {
      _last = null;
      unawaited(_ticker.start());
    }
  }

  void _tick(Duration now) {
    if (_drops.list.isNotEmpty) {
      _drops.age = (now - (_drops.born ??= now)).inMicroseconds / 1e6;
      if (_drops.age > 1.2) _drops.list = const [];
      _drops.changed();
    }
    final dt = _last == null ? 0.0 : (now - _last!).inMicroseconds / 1e6;
    _last = now;
    // Caustics: in over about a second, out over about two.
    final target = _target;
    final rate = target > _level ? 1.2 : 0.6;
    _level = target > _level
        ? (_level + rate * dt).clamp(0, target)
        : (_level - rate * dt).clamp(target, 1);
    _stirred = (_stirred - 1.4 * dt).clamp(0, 1);
    _caustics
      ..time += dt * (0.8 + 0.6 * _stirred)
      ..strength = Curves.easeInOut.transform(_level) * (1 + _stirred)
      ..changed();
    _floorCaustics
      ..time = _caustics.time
      ..strength = _caustics.strength
      ..changed();
    final ripples = _painter.ripples;
    for (final r in ripples) {
      r.age = (now - (r.born ??= now)).inMicroseconds / 1e6;
    }
    ripples.removeWhere((r) => r.age >= r.life);
    if (ripples.isEmpty) {
      _snapshot.allowSnapshotting = false;
      if (_level == 0 && target == 0 && _drops.list.isEmpty) _ticker.stop();
      return;
    }
    // What's under the surface may have changed (a reply streaming in):
    // snapshot it again, then bend it.
    _snapshot.clear();
    _painter.changed();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _ticker.dispose();
    _caustics.dispose();
    _floorCaustics.dispose();
    _drops.dispose();
    _snapshot.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = NushiTheme.of(context).t;
    final dark = t.brightness == Brightness.dark;
    final light = dark
        ? t.shineBand.withValues(alpha: 0.13)
        : t.accent.withValues(alpha: 0.10);
    _caustics.color = light;
    _floorCaustics.color = light;
    _drops.color = dark ? t.shineBand : t.accent;
    _painter
      ..dark = dark
      ..crest = dark ? t.shineBand : t.accent
      ..crestStrength = dark ? 0.12 : 0.1
      ..glint = t.gold
      ..glintStrength = dark ? 0.3 : 0.28;
    return KeyedSubtree(key: _area, child: widget.child);
  }

  /// The transcript's water: what ripples ([PondSurface]).
  Widget _surface(BuildContext context, Widget child) {
    final t = NushiTheme.of(context).t;
    final surface = SnapshotWidget(
      key: _key,
      controller: _snapshot,
      painter: _painter,
      mode: SnapshotMode.permissive,
      // The pond's own water: troughs darken it and crests light it, even
      // where the transcript leaves the pane showing through.
      child: ColoredBox(
        color: t.base,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // The light on the pond's floor, under the text.
            Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: _caustics)),
            ),
            child,
          ],
        ),
      ),
    );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        surface,
        // Drops a splash throws up, over the text, crisp.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: RepaintBoundary(child: CustomPaint(painter: _drops)),
            ),
          ),
        ),
      ],
    );
  }

  /// Under the transcript (the turn line, the composer): the same light
  /// on the floor, carried on from the water above ([PondFloor]).
  Widget _floor(Widget child) => Stack(
    key: _floorKey,
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: RepaintBoundary(child: CustomPaint(painter: _floorCaustics)),
      ),
      child,
    ],
  );
}

/// The water that ripples: the transcript's list, under a [Pond] that
/// holds it and what's under it. Without a pond, just [child].
class PondSurface extends StatelessWidget {
  const PondSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      context.findAncestorStateOfType<_PondState>()?._surface(context, child) ??
      child;
}

/// What's under the transcript in a [Pond] (the turn line, the composer):
/// the caustics carry on under it. Without a pond, just [child].
class PondFloor extends StatelessWidget {
  const PondFloor({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      context.findAncestorStateOfType<_PondState>()?._floor(child) ?? child;
}

class _DropsPainter extends ChangeNotifier implements CustomPainter {
  List<_Drop> list = const [];
  Duration? born;
  double age = 0;
  Color color = const Color(0xFFFFFFFF);
  final _paint = Paint()..strokeCap = StrokeCap.round;

  void changed() => notifyListeners();

  @override
  void paint(Canvas canvas, Size size) {
    const g = 1100.0;
    final a = age;
    for (final d in list) {
      final vy = d.vy + g * a;
      final p = Offset(d.x + d.vx * a, size.height + d.vy * a + g * a * a / 2);
      if (p.dy > size.height + 4) continue; // back in the water
      final fade = (1 - a / 1.2).clamp(0.0, 1.0);
      // A round drop, a faint wake behind it.
      final tail = Offset(d.vx, vy) * 0.008;
      _paint
        ..strokeWidth = d.size * 0.7
        ..color = color.withValues(alpha: 0.25 * fade);
      canvas.drawLine(p, p - tail, _paint);
      _paint.color = color.withValues(alpha: 0.85 * fade);
      canvas.drawCircle(p, d.size / 2, _paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter old) => true;

  @override
  bool? hitTest(Offset position) => false;

  @override
  SemanticsBuilderCallback? get semanticsBuilder => null;

  @override
  bool shouldRebuildSemantics(CustomPainter old) => false;
}

class _RipplePainter extends SnapshotPainter {
  final ripples = <_Ripple>[];
  bool dark = true;
  Color crest = const Color(0xFFFFFFFF);
  double crestStrength = 0.5;
  Color glint = const Color(0xFFF5A524);
  double glintStrength = 0.9;
  ui.FragmentShader? _shader;
  final _paint = Paint();

  void changed() => notifyListeners();

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) => painter(context, offset);

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    final program = Pond._program;
    if (program == null) return;
    final shader = _shader ??= program.fragmentShader();
    var i = 0;
    void f(double v) => shader.setFloat(i++, v);
    f(size.width);
    f(size.height);
    for (var n = 0; n < 3; n++) {
      if (n < ripples.length) {
        final r = ripples[n];
        f(r.at.dx);
        f(r.at.dy);
        f(r.age);
        f(r.kind);
      } else {
        f(0);
        f(0);
        f(-1);
        f(0);
      }
    }
    f(crest.r);
    f(crest.g);
    f(crest.b);
    f(crestStrength);
    f(glint.r);
    f(glint.g);
    f(glint.b);
    f(glintStrength);
    f(dark ? 1 : 0);
    shader.setImageSampler(0, image);
    _paint.shader = shader;
    final canvas = context.canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    canvas
      ..drawRect(Offset.zero & size, _paint)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant SnapshotPainter oldPainter) => true;
}

class _CausticsPainter extends ChangeNotifier implements CustomPainter {
  _CausticsPainter(this._region, this._area);

  // Where this painter is, in the whole pond: the floor's cells run on
  // from the water's.
  final GlobalKey _region;
  final GlobalKey _area;
  double time = 0;
  double strength = 0;
  Color color = const Color(0x22FFFFFF);
  ui.FragmentShader? _shader;
  final _paint = Paint();

  void changed() => notifyListeners();

  @override
  void paint(Canvas canvas, Size size) {
    final program = Pond._caustics;
    if (program == null || strength <= 0.001) return;
    final region = _region.currentContext?.findRenderObject() as RenderBox?;
    final area = _area.currentContext?.findRenderObject() as RenderBox?;
    var origin = Offset.zero;
    var full = size;
    if (region != null && area != null && region.attached && area.attached) {
      origin = region.localToGlobal(Offset.zero, ancestor: area);
      full = area.size;
    }
    final shader = _shader ??= program.fragmentShader();
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, origin.dx)
      ..setFloat(3, origin.dy)
      ..setFloat(4, full.width)
      ..setFloat(5, full.height)
      ..setFloat(6, time)
      ..setFloat(7, strength)
      ..setFloat(8, color.r)
      ..setFloat(9, color.g)
      ..setFloat(10, color.b)
      ..setFloat(11, color.a);
    _paint.shader = shader;
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(CustomPainter old) => true;

  @override
  bool? hitTest(Offset position) => false;

  @override
  SemanticsBuilderCallback? get semanticsBuilder => null;

  @override
  bool shouldRebuildSemantics(CustomPainter old) => false;
}

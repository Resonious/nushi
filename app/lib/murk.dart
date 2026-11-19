import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:nushi/motion.dart';
import 'package:nushi/pond.dart';

/// The chat pane while a new chat starts: silt stirs and the water
/// clouds, the transcript and its composer ([MurkWater]) dimming and
/// blurring as the agent starts. When the new chat comes ([place] changed
/// as it clears) its water rises out of the murk and a drop falls in its
/// empty pond ([Pond.welcome]); a start that ends where it began
/// (cancelled, failed) clears quickly. What frames the water (the
/// header, the details pane: [MurkFrame]) stays where it is, only
/// fading a little as what it says changes. With Reduce Motion, nothing
/// clouds.
class Murk extends StatefulWidget {
  const Murk({
    required this.murky,
    required this.place,
    required this.child,
    super.key,
  });

  /// A chat is starting.
  final bool murky;

  /// What the pane shows (the chat's id).
  final Object? place;

  final Widget child;

  @override
  State<Murk> createState() => _MurkState();
}

class _MurkState extends State<Murk> with SingleTickerProviderStateMixin {
  late final _murk = AnimationController(vsync: this);
  // Where the pane was as it clouded.
  Object? _from;
  bool _rising = false;
  // Rising from no chat at all (an empty window): what frames it is new
  // too, and comes in with it.
  bool _fresh = false;
  Timer? _drop;

  @override
  void initState() {
    super.initState();
    if (widget.murky) _cloud();
  }

  @override
  void didUpdateWidget(Murk old) {
    super.didUpdateWidget(old);
    if (widget.murky && !old.murky) {
      _cloud();
    } else if (!widget.murky && old.murky) {
      _clear();
    }
  }

  void _cloud() {
    _from = widget.place;
    _rising = false;
    _fresh = false;
    _drop?.cancel();
    if (reduceMotion(context)) return;
    unawaited(
      _murk.animateTo(
        1,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _clear() {
    _rising = widget.place != _from;
    _fresh = _rising && _from == null;
    if (reduceMotion(context)) {
      _murk.value = 0;
      return;
    }
    if (!_rising) {
      unawaited(
        _murk.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
      return;
    }
    // From the murk's thickest: the new chat wasn't seen through it.
    _murk.value = 1;
    unawaited(
      _murk.animateTo(
        0,
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutCubic,
      ),
    );
    // As it clears, before it's still: a drop in the new pond.
    _drop = Timer(const Duration(milliseconds: 260), () {
      if (mounted) Pond.welcome(context);
    });
  }

  @override
  void dispose() {
    _drop?.cancel();
    _murk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _MurkScope(state: this, child: widget.child);
}

class _MurkScope extends InheritedWidget {
  const _MurkScope({required this.state, required super.child});

  final _MurkState state;

  @override
  bool updateShouldNotify(_MurkScope old) => old.state != state;
}

/// The water under a [Murk]: the transcript and its composer cloud,
/// and rise as a new chat comes. Without a murk, just [child].
class MurkWater extends StatelessWidget {
  const MurkWater({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final murk = context.getInheritedWidgetOfExactType<_MurkScope>()?.state;
    if (murk == null) return child;
    return AnimatedBuilder(
      animation: murk._murk,
      // The same tree clear or murky: what's in it keeps its state.
      builder: (context, child) {
        final v = murk._murk.value;
        final rising = murk._rising;
        final sigma = (rising ? 7.0 : 3.5) * v;
        return Transform.translate(
          offset: Offset(0, rising ? 18 * v : 0),
          child: ImageFiltered(
            enabled: sigma > 0.05,
            imageFilter: ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.decal,
            ),
            child: Opacity(
              opacity: 1 - (rising ? 0.7 : 0.45) * v,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// What frames the water under a [Murk] (the chat's header, its details
/// pane): it stays put and sharp, dimming a little while the water
/// clouds and as what it says changes. Where there was no chat before (an
/// empty window), it wasn't there either: it fades in as the water
/// rises, a pane at the side ([slide]) gliding in from the window's edge.
/// Without a murk, just [child].
class MurkFrame extends StatelessWidget {
  const MurkFrame({required this.child, super.key, this.slide = false});

  final Widget child;

  /// It's a pane at the right: new, it glides in from the right.
  final bool slide;

  @override
  Widget build(BuildContext context) {
    final murk = context.getInheritedWidgetOfExactType<_MurkScope>()?.state;
    if (murk == null) return child;
    return AnimatedBuilder(
      animation: murk._murk,
      builder: (context, child) {
        final v = murk._murk.value;
        if (murk._fresh) {
          return FractionalTranslation(
            translation: Offset(slide ? 0.35 * v : 0, 0),
            child: Opacity(opacity: (1 - v).clamp(0, 1), child: child),
          );
        }
        return Opacity(
          opacity: 1 - (murk._rising ? 0.5 : 0.3) * v,
          child: child,
        );
      },
      child: child,
    );
  }
}

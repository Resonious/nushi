part of 'controls.dart';

/// A pill-shaped button on a card (ADR 0111): [label], an optional leading
/// [icon], on the card's lifted fill, no outline. In the composer's row
/// (Queue, Stop and send); [small], in a tool call's row (Preview, Open),
/// where [on] fills it with the accent's soft tint while what it opens is
/// the one open.
class PillButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.tooltip = '',
    this.small = false,
    this.on = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String tooltip;
  final bool small;
  final bool on;

  /// The composer's row's height: its pills, pickers and round buttons.
  static const height = 32.0;

  /// A [small] pill's height.
  static const smallHeight = 24.0;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final fg = on ? t.accentInk : t.text;
    final fill = on ? t.accentSoft : t.lifted;
    final round = BorderRadius.circular(NushiTheme.pill);
    return Pressable(
      onTap: onPressed,
      tooltip: tooltip,
      builder: (context, look) => _faded(
        look,
        Container(
          height: small ? smallHeight : height,
          padding: EdgeInsets.symmetric(horizontal: small ? 10 : 12),
          decoration: BoxDecoration(
            color: look.hover ? Color.alphaBlend(_tint(t, look), fill) : fill,
            borderRadius: round,
          ),
          foregroundDecoration: focusRing(t, look, radius: round),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: small ? 5 : 6,
            children: [
              if (icon != null)
                Icon(
                  icon,
                  size: small ? 13 : 15,
                  color: on ? fg : t.textSecondary,
                ),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.ui(
                    fg,
                    size: small ? 12 : 13,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a [RoundButton] is for, which says its fill.
enum RoundKind {
  /// One more thing to do (the composer's +, a pill's action without its
  /// words): the card's lifted fill.
  plain,

  /// The one main action (Send): the accent's fill.
  primary,
}

/// A round icon button on a card (ADR 0111), [PillButton.height] across:
/// [glyph] draws its mark in the color its [kind] gives.
class RoundButton extends StatelessWidget {
  const new({
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.kind = RoundKind.plain,
  });

  final Widget Function(Color color) glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final RoundKind kind;

  @override
  Widget build(BuildContext context) {
    final t = NushiTheme.of(context).t;
    final (fill, fg) = switch (kind) {
      RoundKind.plain => (t.lifted, t.text),
      RoundKind.primary => (t.accent, t.onAccent),
    };
    final round = BorderRadius.circular(NushiTheme.pill);
    return Pressable(
      onTap: onPressed,
      tooltip: tooltip,
      builder: (context, look) => _faded(
        look,
        Container(
          width: PillButton.height,
          height: PillButton.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: look.pressed && kind == RoundKind.primary
                ? t.accentPressed
                : look.hover
                ? Color.alphaBlend(_tint(t, look), fill)
                : fill,
            borderRadius: round,
          ),
          foregroundDecoration: kind == RoundKind.primary
              ? accentFocusRing(t, look, radius: round)
              : focusRing(t, look, radius: round),
          child: glyph(fg),
        ),
      ),
    );
  }
}

/// What a [NotePill] says by its colours: a state's ink on its soft fill
/// (`docs/design.md`'s States), or [quiet], a state that asks for nothing.
enum NoteTone { quiet, accent, done, needs, crashed }

/// A short note in a pill, as `PhasePill` draws a chat's state: [label] in
/// its [tone]'s ink on that ink's soft fill, never a faint word. With
/// [onTap] it's a button (the hover and press tints, the focus ring, the
/// hand) and [trailing] says where it goes; [tip] is its tooltip. A file's
/// change marks' word on the Files pane's path row (ADR 0131).
class NotePill extends StatelessWidget {
  const new(
    this.label, {
    super.key,
    this.tone = NoteTone.quiet,
    this.onTap,
    this.tip = '',
    this.trailing,
  });

  final String label;
  final NoteTone tone;
  final VoidCallback? onTap;
  final String tip;
  final IconData? trailing;

  /// Its height.
  static const height = 22.0;

  /// [tone]'s ink and fill.
  static (Color, Color) colors(Tokens t, NoteTone tone) => switch (tone) {
    NoteTone.quiet => (t.textSecondary, t.raised),
    NoteTone.accent => (t.accentInk, t.accentSoft),
    NoteTone.done => (t.done, t.doneSoft),
    NoteTone.needs => (t.needs, t.needsSoft),
    NoteTone.crashed => (t.crashed, t.crashedSoft),
  };

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final (ink, fill) = colors(t, tone);
    final round = BorderRadius.circular(NushiTheme.pill);
    Widget pill(ControlLook? look) => Container(
      height: height,
      padding: EdgeInsets.only(left: 9, right: trailing == null ? 9 : 5),
      decoration: BoxDecoration(
        color: look != null && look.hover
            ? Color.alphaBlend(_tint(t, look), fill)
            : fill,
        borderRadius: round,
      ),
      foregroundDecoration: look == null
          ? null
          : focusRing(t, look, radius: round),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.ui(ink, size: 12, weight: FontWeight.w600),
            ),
          ),
          if (trailing case final icon?) Icon(icon, size: 14, color: ink),
        ],
      ),
    );
    if (onTap == null) {
      final plain = pill(null);
      return tip.isEmpty ? plain : tooltip(context, tip, plain);
    }
    return Pressable(
      onTap: onTap,
      tooltip: tip,
      builder: (_, look) => pill(look),
    );
  }
}

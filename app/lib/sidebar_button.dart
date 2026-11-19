import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:nushi/app_actions.dart';
import 'package:nushi/chat_view.dart';
import 'package:nushi/controls.dart';
import 'package:nushi/conventions.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/native.dart';
import 'package:nushi/panes.dart';
import 'package:nushi/project_rail.dart';
import 'package:nushi/run_state.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/sidebar.dart';
import 'package:nushi/sidebar_view.dart';
import 'package:nushi/theme/theme.dart';

part 'sidebar_glide.dart';

/// Where what's in the main pane's top may start with the sidebar hidden,
/// from the pane's left edge: past the Mac's traffic lights, which sit
/// level with the header's middle (ADR 0111), or the window's own inset
/// (`AppWindow.titleInset`), less the window's margin, which the pane is
/// already in by (ADR 0111). The phone, whose sidebar never hides, has none.
double get lightsInset =>
    isPhone ? 0 : max(8, native.window.titleInset - NushiTheme.windowPad);

/// Where a header's own content starts with the sidebar hidden, from the
/// pane's left edge: past the lights and [TitleButtons], with the room a
/// header's icon button leaves around its icon after them.
double get hiddenHeaderStart =>
    TitleButtons.right - NushiTheme.windowPad + SidebarButton.iconInset;

/// Whether the sidebar is hidden, so the main area reaches the window's left
/// edge: hidden by the user, or tucked away for a narrow window
/// ([sidebarTucked]). The phone has none, whatever is saved.
bool get sidebarShut =>
    !isPhone && (sidebarHidden.value || sidebarTucked.value);

/// Whether the sidebar, shown by the user, is tucked away because the
/// window would leave the main area beside it narrower than a chat's least
/// ([sidebarTucksIn]); never saved, so it's back as soon as the window is
/// wide enough. `NushiApp` sets it as it lays the window out, before what
/// reads [sidebarShut] below it is laid out in the same frame.
final ValueNotifier<bool> sidebarTucked = runValue(false);

/// The sidebar's width as first shown, before it's dragged.
const sidebarInitial = 260.0;

/// The widest the sidebar is dragged in a window [window] wide: it leaves
/// the main area 560.
double sidebarMost(double window) => min(480, window - 560);

/// The narrowest the sidebar is dragged in a window [window] wide: with
/// the project rail wanted, no narrower than it needs, as far as the
/// window has room.
double sidebarLeast(double window) => railWanted
    ? min(ProjectRail.minSidebar, max(Sidebar.minWidth, sidebarMost(window)))
    : Sidebar.minWidth;

/// The sidebar's width in a window [window] wide, as `Resizable` gives it:
/// as dragged, within its least and most ([sidebarLeast] wins).
double sidebarWidthIn(double window) {
  final least = sidebarLeast(window);
  return paneWidth(
    'sidebar',
    sidebarInitial,
  ).clamp(least, max(least, sidebarMost(window)));
}

/// Whether a window [window] wide tucks the shown sidebar away: beside it,
/// the main area (less the window's margin at its right) would be
/// narrower than [ChatView.leastBesideWide], the least a chat's transcript
/// is ever laid out at, beside the side panes or under them (ADR 0123).
/// Wider, the sidebar shows; the panes then decide on the room it leaves.
bool sidebarTucksIn(double window) =>
    window - sidebarWidthIn(window) - NushiTheme.windowPad <
    ChatView.leastBesideWide;

/// Each ask to see the sidebar while it's tucked away: the button, ⌘\,
/// the palette and the menu bar float it over the view, as a peek
/// (`SidebarBeside`), or put a peek away.
final ValueNotifier<int> sidebarPeekAsks = runValue(0);

/// Hides the sidebar, or shows it again (the button, ⌘\, the palette and
/// the menu bar). While it's tucked away for a narrow window, it floats
/// over the view instead, and the user's choice stays as it is.
void toggleSidebar() {
  if (sidebarTucked.value && !sidebarHidden.value) {
    sidebarPeekAsks.value++;
    return;
  }
  sidebarHidden.value = !sidebarHidden.value;
}

/// The button that hides the sidebar or shows it, the box of
/// [LineIcon.sidebar] with its left side marked off. It's the first of
/// [TitleButtons], at one place in the window whether the sidebar shows or
/// not (ADR 0118: a toggle never moves when pressed), and the same control
/// as the icon buttons at a header's right (32 square, [IconTap.header];
/// ADR 0111), so the two ends of the top match.
class SidebarButton extends StatelessWidget {
  const new({super.key});

  /// How far in from its box its icon sits less a header's icon button's
  /// room around it: the icon is [iconInset] past where the lights leave
  /// room ([lightsInset]).
  static const iconInset = 5.0;

  /// How far its box reaches before that place, around the icon.
  static const double reach = IconTap.header - iconInset;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([sidebarHidden, sidebarTucked]),
    builder: (context, _) => IconTap.line(
      LineIcon.sidebar,
      tooltip: withKey(
        '${sidebarShut ? 'Show' : 'Hide'} the sidebar',
        Act.sidebar.shortcut ?? '',
      ),
      padding: IconTap.header,
      onTap: toggleSidebar,
    ),
  );
}

/// The buttons at the window's top left, past the traffic lights, level
/// with the headers' middle: [SidebarButton], then Back and Forward
/// through the places visited (`goBack`, ADR 0119), each greyed
/// out while there's nowhere to go. They're drawn over the
/// sidebar's top strip and the main pane's header alike, at the same place
/// in the window whether the sidebar shows, is hidden or slides (ADR
/// 0118); `SidebarBeside` puts them there. [onSidebarHover] hears the
/// pointer come onto the sidebar's button and leave it.
class TitleButtons extends StatelessWidget {
  const new({required this.daemon, super.key, this.onSidebarHover});

  final Daemon daemon;
  final ValueChanged<bool>? onSidebarHover;

  /// A button's box: a header's icon button.
  static const double _box = 16 + 2 * IconTap.header;

  /// How many there are.
  static const _count = 3;

  /// Where they start, from the window's left edge: the first one's icon
  /// [SidebarButton.iconInset] past the lights.
  static double get left =>
      NushiTheme.windowPad + lightsInset - SidebarButton.reach;

  /// How wide they are together.
  static double get width => _count * _box + (_count - 1) * NushiTheme.iconGap;

  /// Where they end, from the window's left edge.
  static double get right => left + width;

  /// How far down from the window's top they are, and how tall: a header's
  /// row, under the window's margin, less its hairline.
  static const double top = NushiTheme.windowPad;
  static const double height = PaneHeader.height - 1;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => onSidebarHover?.call(true),
          onExit: (_) => onSidebarHover?.call(false),
          child: const SidebarButton(),
        ),
        const SizedBox(width: NushiTheme.iconGap),
        // What they can do changes as the daemon does: a chat archived or
        // deleted is passed over.
        ListenableBuilder(
          listenable: daemon,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTap.line(
                LineIcon.chevronBack,
                tooltip: withKey('Back', Act.back.shortcut ?? ''),
                padding: IconTap.header,
                onTap: daemon.canGoBack ? daemon.goBack : null,
              ),
              const SizedBox(width: NushiTheme.iconGap),
              IconTap.line(
                LineIcon.chevronForward,
                tooltip: withKey('Forward', Act.forward.shortcut ?? ''),
                padding: IconTap.header,
                onTap: daemon.canGoForward ? daemon.goForward : null,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

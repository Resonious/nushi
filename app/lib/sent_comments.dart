import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nushi/menu.dart';
import 'package:nushi/review.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/widgets.dart';

/// Whether [c] was sent and its lines have changed since: the agent has
/// it, and it no longer stands on any line. It shows in [SentComments],
/// not as a card, until the turn that took it ends ([filesRead]).
bool sentAndChanged(ReviewComment c) => c.sent && c.outdated;

/// Above a diff's first line, at its right: a quiet "2 sent" pill for the
/// file's comments that were sent and whose lines changed since
/// ([sentAndChanged]). They're done with, so they leave the code alone:
/// the pill says they were there, and its popover lists each (its lines,
/// their text as they were, the comment) with Remove ([onRemove]). A row
/// [height] high, its own, so it never covers a line of code. A click on
/// the pill, outside the list or Escape closes it.
class SentComments extends StatefulWidget {
  const new(this.sent, {required this.onRemove, super.key});

  final List<ReviewComment> sent;
  final ValueChanged<ReviewComment> onRemove;

  /// Its row's height: the old side of a side-by-side diff keeps as much
  /// room above its first line, so the two sides stay level.
  static const height = 30.0;

  @override
  State<SentComments> createState() => _SentCommentsState();
}

class _SentCommentsState extends State<SentComments> {
  final _menu = MenuController();

  /// Held while the list is open, for its Escape: the list's rows take no
  /// focus of their own, and the click left it where it was.
  final _focus = FocusNode(debugLabel: 'sent comments');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    _menu.close();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final sent = widget.sent;
    if (sent.isEmpty) return const SizedBox(height: SentComments.height);
    final n = sent.length;
    return SizedBox(
      height: SentComments.height,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          // At the diff's right edge: its popover ends under the pill.
          child: TrailingMenus(
            child: Menu(
              controller: _menu,
              filter: false,
              onOpen: _focus.requestFocus,
              onClose: _focus.unfocus,
              entries: [
                const MenuEntry.heading(
                  'Sent to the agent. The lines changed since.',
                ),
                for (final c in sent)
                  MenuEntry.row(
                    (_) => _SentRow(c, onRemove: () => widget.onRemove(c)),
                  ),
              ],
              builder: (context, open) => Focus(
                focusNode: _focus,
                skipTraversal: true, // focused only while the list is open
                onKeyEvent: _key,
                child: NotePill(
                  '$n sent',
                  icon: Icons.history,
                  tip: n == 1
                      ? 'A comment sent to the agent; its lines changed since'
                      : '$n comments sent to the agent; their lines changed '
                            'since',
                  onTap: open,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sent comment in [SentComments]' popover: its lines, their text as it
/// was (a few lines at most) and the comment, Remove at its right.
class _SentRow extends StatelessWidget {
  const new(this.comment, {required this.onRemove});

  final ReviewComment comment;
  final VoidCallback onRemove;

  /// Its width: a comment's line or two, in a window as narrow as 720.
  static const _width = 320.0;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final c = comment;
    return SizedBox(
      width: _width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 3,
                children: [
                  Text(c.lines, style: theme.ui(t.textMuted, size: 11.5)),
                  Text(
                    c.quote,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.code(t.textSecondary, size: 11.5),
                  ),
                  Text(c.text, style: theme.ui(t.text)),
                ],
              ),
            ),
            IconTap(Icons.close, tooltip: 'Remove', size: 13, onTap: onRemove),
          ],
        ),
      ),
    );
  }
}

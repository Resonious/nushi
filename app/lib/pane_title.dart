import 'package:flutter/widgets.dart';

import 'package:nushi/text_width.dart';

/// A pane's name and what it says after it, in its top row (a `PaneHeader`),
/// taking the room the row leaves it and never more: [caption] takes what
/// [title] leaves, cut short with an ellipsis; with less room than [title]
/// and a few letters of it, [caption] goes and [title] is cut short; with
/// too little for even that, both go (a pane narrowed for a narrow window,
/// ADR 0123). Each is a one-line [Text] with its own style.
class PaneTitle extends StatelessWidget {
  const new({required this.title, this.caption, this.gap = 8, super.key});

  final Text title;
  final Text? caption;
  final double gap;

  /// The least a caption is worth showing at: fewer than a few letters say
  /// nothing.
  static const captionLeast = 40.0;

  /// The least room a cut title is shown in.
  static const titleLeast = 24.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final room = box.maxWidth;
      final width = textWidth(
        context,
        title.data!,
        title.style ?? const TextStyle(),
      );
      Text cut(Text t) => Text(
        t.data!,
        style: t.style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
      final caption = this.caption;
      if (caption != null && room >= width + gap + captionLeast) {
        return Row(
          children: [
            title,
            SizedBox(width: gap),
            Expanded(child: cut(caption)),
          ],
        );
      }
      if (room >= width) return Row(children: [title]);
      if (room >= titleLeast) {
        return Row(children: [Flexible(child: cut(title))]);
      }
      return const SizedBox.shrink();
    },
  );
}

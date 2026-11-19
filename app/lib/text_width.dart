import 'package:flutter/widgets.dart';

/// How wide [text] sets on one line in [style] where [context] is: at its
/// text scale and, with [merge], over its default text style, as a [Text]
/// there sets it; without, [style] alone.
double textWidth(
  BuildContext context,
  String text,
  TextStyle style, {
  bool merge = true,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: merge ? DefaultTextStyle.of(context).style.merge(style) : style,
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

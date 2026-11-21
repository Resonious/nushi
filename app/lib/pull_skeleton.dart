import 'package:flutter/material.dart';
import 'package:nushi/pull_header.dart' show pullPad;
import 'package:nushi/theme/theme.dart';

/// The Pull request tab before its pull request was ever read: its head
/// (a pill, the title, the branches) and the merge status card's rows as
/// bars in the tab's column, so the page's shape is there at once.
class PullSkeleton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final t = NushiTheme.of(context).t;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: t.lifted,
        borderRadius: BorderRadius.circular(NushiTheme.tag),
      ),
    );
    Widget box(Widget child) =>
        DecoratedBox(decoration: cardBox(t), child: child);
    return Semantics(
      label: 'Loading the pull request',
      child: LayoutBuilder(
        builder: (context, size) => ListView(
          padding: EdgeInsets.fromLTRB(
            pullPad(size.maxWidth),
            68,
            pullPad(size.maxWidth),
            16,
          ),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.5,
              child: bar(double.infinity, 20),
            ),
            const SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [bar(52, 18), bar(140, 14), bar(160, 14)],
            ),
            const SizedBox(height: 20),
            Row(
              spacing: 16,
              children: [
                for (final w in const [64.0, 70.0, 70.0, 96.0]) bar(w, 12),
              ],
            ),
            const SizedBox(height: 24),
            box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      spacing: 12,
                      children: [
                        bar(32, 32),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 6,
                            children: [bar(140, 12), bar(260, 9)],
                          ),
                        ),
                        bar(150, 28),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: t.line),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      spacing: 24,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 10,
                              children: [bar(110, 11), bar(double.infinity, 6)],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            box(
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    for (final f in [0.9, 0.75, 0.6])
                      FractionallySizedBox(
                        widthFactor: f,
                        child: bar(double.infinity, 10),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

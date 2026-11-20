import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/review.dart';
import 'package:nushi/review_cards.dart';

import 'fake_daemon.dart' show loadFonts;
import 'harness.dart';

void main() {
  setUpAll(loadFonts);

  for (final sent in [false, true]) {
    testWidgets('a comment card stays as it is under the pointer: its '
        "buttons' room is kept (sent: $sent)", (tester) async {
      viewport(tester, const Size(600, 300));
      await tester.pumpWidget(
        themed(
          Align(
            alignment: Alignment.topLeft,
            child: CommentCard(
              ReviewComment(
                id: 'c1',
                where: '',
                old: false,
                path: 'lib/a.dart',
                start: 25,
                end: 25,
                quote: 'const size = 10',
                text: 'Should this be a setting?',
                outdated: true,
                sent: sent,
              ),
              onEdit: () {},
              onRemove: () {},
            ),
          ),
        ),
      );
      final card = find.byType(CommentCard);
      final text = find.text('Should this be a setting?');
      final was = (tester.getRect(card), tester.getRect(text));
      expect(find.byTooltip('Remove').hitTestable(), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pump();
      expect(find.byTooltip('Remove').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Edit'), sent ? findsNothing : findsOneWidget);
      expect((tester.getRect(card), tester.getRect(text)), was);
    });
  }
}

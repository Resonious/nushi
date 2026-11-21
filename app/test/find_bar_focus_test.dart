import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/transcript_find.dart';

import 'harness.dart';

// Typing in a long chat's find goes to a match near the top of what's
// loaded, so earlier messages load and the bar says so under its field.
// The field is the same one before, while and after: one built anew has
// the focus and no keyboard, so nothing more could be typed.
void main() {
  testWidgets("the field stays as the bar's line comes and goes", (
    tester,
  ) async {
    final chatFind = Find()..open();
    addTearDown(chatFind.dispose);
    Future<void> bar({bool loading = false, VoidCallback? loadAll}) =>
        tester.pumpWidget(
          themed(
            Center(
              child: FindBar(chatFind, loading: loading, loadAll: loadAll),
            ),
          ),
        );
    EditableTextState field() => tester.state(find.byType(EditableText));
    await bar();
    await tester.pump();
    final first = field();
    await tester.enterText(find.byType(TextField), 'f');

    await bar(loading: true);
    expect(find.text('Loading earlier messages…'), findsOneWidget);
    expect(field(), same(first));

    await bar(loadAll: () {});
    expect(find.text('Load all'), findsOneWidget);
    expect(field(), same(first));

    await bar();
    expect(field(), same(first));
    expect(chatFind.focus.hasFocus, isTrue);
    expect(first.textEditingValue.text, 'f');
  });
}

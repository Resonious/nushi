import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/controls.dart' show Toggle;
import 'package:nushi/settings_rows.dart';
import 'package:nushi/theme/theme.dart';

import 'harness.dart';

void main() {
  testWidgets('a switch whose change is a call: tapped twice while it runs, '
      'it sends once; its error shows', (tester) async {
    final asked = <bool>[];
    var call = Completer<void>();
    await tester.pumpWidget(
      themed(
        Center(
          child: SettingsSwitch(
            value: false,
            run: ({required on}) {
              asked.add(on);
              return call.future;
            },
          ),
        ),
        tokens: Tokens.light,
      ),
    );
    Toggle shown() => tester.widget<Toggle>(find.byType(Toggle));

    await tester.tap(find.byType(Toggle));
    await tester.pump();
    expect(shown().onChanged, isNull); // held while the call runs
    await tester.tap(find.byType(Toggle));
    await tester.pump();
    expect(asked, [true]);

    call.complete();
    await tester.pumpAndSettle();
    expect(shown().onChanged, isNotNull);

    call = Completer<void>();
    await tester.tap(find.byType(Toggle));
    call.completeError(StateError('no daemon'));
    await tester.pumpAndSettle();
    expect(asked, [true, true]);
    expect(find.text('Bad state: no daemon'), findsOne);
    expect(shown().onChanged, isNotNull);
  });

  for (final tokens in [Tokens.dark, Tokens.light]) {
    testWidgets(
      'on and off look unmistakably apart, ${tokens.brightness.name}: '
      'a solid track each, the same knob, only its place moves',
      (tester) async {
        var on = false;
        await tester.pumpWidget(
          themed(
            Center(
              child: StatefulBuilder(
                builder: (context, set) => SettingsSwitch(
                  value: on,
                  onChanged: (v) => set(() => on = v),
                ),
              ),
            ),
            tokens: tokens,
          ),
        );
        final track = find.descendant(
          of: find.byType(Toggle),
          matching: find.byType(AnimatedContainer),
        );
        final knob = find.descendant(
          of: track,
          matching: find.byType(Container),
        );
        Color fill() =>
            ((tester.widget<AnimatedContainer>(track).decoration!
                    as BoxDecoration)
                .color)!;
        final offFill = fill();
        final offKnob = tester.getRect(knob.last);
        // Off: a grey of real strength, not the card's own fill.
        expect(offFill, Toggle.offTrack(tokens));
        expect(offFill.a, greaterThan(0.5));
        expect(offFill, isNot(tokens.raised));

        await tester.tap(find.byType(Toggle));
        await tester.pumpAndSettle();
        expect(on, isTrue);
        expect(fill(), tokens.accent);
        final onKnob = tester.getRect(knob.last);
        expect(onKnob.size, offKnob.size);
        expect(onKnob.left, greaterThan(offKnob.left + 10));
        expect(tester.getSize(find.byType(Toggle)), Toggle.size);
        expect(
          tester.getSemantics(find.byType(Toggle)),
          matchesSemantics(
            hasToggledState: true,
            isToggled: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            isFocusable: true,
            hasFocusAction: true,
          ),
        );
      },
    );
  }
}

// Every section of Settings over the whole app, at 1700 and 900 wide, in
// both themes, to look at (not compared, not part of make test):
// NUSHI_RENDERS=<folder> flutter test test/screenshots/settings_shots.dart
// writes <section>-<width>-<theme>.png there, and tall-<section>.png, each
// page whole in a tall window. The data is settingsFake's, made up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/native.dart';
import 'package:nushi/place.dart';
import 'package:nushi/settings.dart';

import '../fake_daemon.dart' show loadFonts;
import '../harness.dart';
import '../settings_harness.dart';
import '../spell_harness.dart' show FakeSpeller;

void main() {
  setUpAll(loadFonts);
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);
  const sizes = [(Size(1700, 1000), '1700'), (Size(900, 760), '900')];
  const themes = [(Brightness.dark, 'dark'), (Brightness.light, 'light')];

  for (final s in SettingsSection.values) {
    for (final (size, width) in sizes) {
      for (final (brightness, theme) in themes) {
        testWidgets('${s.name} $width $theme', (tester) async {
          native.speller = FakeSpeller({});
          // One reply card's words changed, as the mocks show it.
          cardAsks.value = {
            'changes': 'Make the changes this review asks for here; commit.',
          };
          final d = await pumpSettingsApp(
            tester,
            settingsFake(),
            s,
            size: size,
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          await render(
            tester,
            find.byType(MaterialApp),
            '${s.name}-$width-$theme',
          );
          await closeView(tester, d);
        }, variant: macOS);
      }
    }
    testWidgets('${s.name} whole', (tester) async {
      native.speller = FakeSpeller({});
      final d = await pumpSettingsApp(
        tester,
        settingsFake(),
        s,
        size: const Size(1300, 2200),
      );
      await render(tester, find.byType(MaterialApp), 'tall-${s.name}');
      await closeView(tester, d);
    }, variant: macOS);
  }

  for (final (size, width) in sizes) {
    testWidgets('a reply card ask in its editor, $width', (tester) async {
      final d = await pumpSettingsApp(
        tester,
        settingsFake(),
        SettingsSection.github,
        size: size,
      );
      final edit = find.byKey(const ValueKey('card-ask-edit-thread'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await render(
        tester,
        find.byType(MaterialApp),
        'github-ask-editor-$width',
      );
      await closeView(tester, d);
    }, variant: macOS);
  }
}

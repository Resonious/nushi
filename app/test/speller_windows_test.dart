import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/speller_windows.dart';

void main() {
  test("the checker is the user's locale's, else its language's first, "
      'else none', () {
    const supported = ['en-US', 'en-GB', 'fr-FR', 'de-DE'];
    expect(language('en-GB', supported), 'en-GB');
    expect(language('EN-gb', supported), 'en-GB');
    expect(language('en-AU', supported), 'en-US');
    expect(language('fr-CA', supported), 'fr-FR');
    expect(language('de', supported), 'de-DE');
    expect(language('ja-JP', supported), isNull);
    expect(language('en-US', const []), isNull);
  });

  // Windows's own checker, in American English (every Windows has it).
  // Never Learn: that writes the user's own dictionary.
  final real = Platform.isWindows ? WindowsSpeller.open(locale: 'en-US') : null;
  test(
    "Windows's checker flags, suggests, and ignores for the session",
    () async {
      final speller = real!;
      expect(await speller.misspelled(['hello', 'wrold', 'there', '']), [
        'wrold',
      ]);
      expect(await speller.guesses('wrold'), contains('world'));
      await speller.ignore('nushiword');
      expect(await speller.misspelled(['nushiword']), isEmpty);
    },
    skip: real == null,
  );
}

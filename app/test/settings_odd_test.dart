import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/settings.dart';

void main() {
  setUpAll(() {
    // An app.json with the Files pane's values of the right type but none
    // the app offers (hand-edited, or another app's): read before anything
    // else is.
    File('$dataDir/app.json')
        .writeAsStringSync(jsonEncode({'tabSize': 3, 'filesTreeSide': 'up'}));
  });

  test('a value the app doesn’t offer reads as the default', () {
    // Only 2, 4 and 8: 3 would reach the tab stops and the editor.
    expect(tabSize.value, 4);
    expect(filesTreeSide.value, TreeSide.automatic);
  });
}

// The phone's record (its key, its name and the Mac it's paired with) in a
// real browser's IndexedDB: every field comes back after a reload.
// Run with: flutter test --platform chrome test/web
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/phone/platform.dart';

void main() {
  test('every field of the record comes back, the host OS too', () async {
    final platform = PhonePlatform();
    final record = <String, Object?>{
      'key': Uint8List.fromList(List.generate(32, (i) => i)),
      'name': 'Phone',
      'relay': 'wss://relay.example',
      'daemon': 'd1',
      'daemonKey': Uint8List.fromList(List.generate(32, (i) => 32 - i)),
      'seen': '2026-11-19T10:00:00.000',
      'os': 'linux',
    };
    await platform.save(record);
    expect(await PhonePlatform().load(), record);
    await platform.clear();
    expect(await platform.load(), isNull);
  });
}

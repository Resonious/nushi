import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/phone/page_frame.dart';
import 'package:nushi/phone/page_frame_stub.dart';
import 'package:nushi/phone/platform.dart';
import 'package:nushi/phone/platform_android.dart';
import 'package:nushi/phone/platform_stub.dart';
import 'package:nushi/phone/scanner.dart';
import 'package:nushi/phone/scanner_stub.dart';
import 'package:nushi/phone/subscription.dart';

void main() {
  test('AndroidPhonePlatform persists pairing, drafts and theme', () async {
    final dir = await Directory.systemTemp.createTemp('nushi-android-test-');
    addTearDown(() => dir.delete(recursive: true));

    final host = AndroidPhonePlatform.forTesting(dir, deviceName: 'Pixel 9');
    phonePlatformHost = host;
    addTearDown(() => phonePlatformHost = null);

    final platform = PhonePlatform();
    expect(platform.nativeApp, isTrue);
    expect(platform.defaultName, 'Pixel 9');
    expect(await platform.pushState(), PushState.unsupported);
    expect(await platform.load(), isNull);
    expect(await platform.loadDrafts(), isNull);
    expect(await platform.loadTheme(), isNull);

    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final daemonKey = Uint8List.fromList(List.generate(32, (i) => 255 - i));
    await platform.save({
      'key': key,
      'name': 'Pixel 9',
      'relay': 'https://relay.example.com',
      'daemon': 'd1',
      'daemonKey': daemonKey,
      'seen': '2026-11-20T00:00:00.000Z',
      'os': 'windows',
    });
    await platform.saveDrafts('{"c1":"hello"}');
    await platform.saveTheme('nord');

    // Fresh instance reads back from disk.
    final again = AndroidPhonePlatform.forTesting(dir, deviceName: 'Pixel 9');
    phonePlatformHost = again;
    final p2 = PhonePlatform();
    final loaded = await p2.load();
    expect(loaded, isNotNull);
    expect(loaded!['key'], key);
    expect(loaded['daemonKey'], daemonKey);
    expect(loaded['name'], 'Pixel 9');
    expect(loaded['relay'], 'https://relay.example.com');
    expect(loaded['daemon'], 'd1');
    expect(loaded['seen'], '2026-11-20T00:00:00.000Z');
    expect(loaded['os'], 'windows');
    expect(await p2.loadDrafts(), '{"c1":"hello"}');
    expect(await p2.loadTheme(), 'nord');

    // Clearing forgets pairing and drafts, keeping the device's theme.
    await p2.clear();
    expect(await p2.load(), isNull);
    expect(await p2.loadDrafts(), isNull);
    expect(await p2.loadTheme(), 'nord');
  });

  testWidgets('PageFrame delegates html and mermaid flag to pageFrameBuilder', (
    tester,
  ) async {
    final calls = <(String, bool)>[];
    pageFrameBuilder = (html, {required mermaid}) {
      calls.add((html, mermaid));
      return const SizedBox.shrink();
    };
    addTearDown(() => pageFrameBuilder = null);

    await tester.pumpWidget(
      const Column(
        children: [
          PageFrame('<p>hi</p>'),
          PageFrame('<html>mermaid</html>', mermaid: true),
        ],
      ),
    );
    expect(calls, [('<p>hi</p>', false), ('<html>mermaid</html>', true)]);
  });

  test('Scanner delegates to scannerBackendFactory', () async {
    final fake = _FakeBackend();
    scannerBackendFactory = () => fake;
    addTearDown(() => scannerBackendFactory = null);

    final scanner = Scanner();
    final seen = <String>[];
    final sub = scanner.codes.listen(seen.add);
    addTearDown(sub.cancel);

    expect(await scanner.start(), isNull);
    expect(fake.started, isTrue);
    fake.emit('https://relay.example.com/#pair?r=1');
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['https://relay.example.com/#pair?r=1']);
    scanner.stop();
    expect(fake.stopped, isTrue);
  });
}

class _FakeBackend implements ScannerBackend {
  final _codes = StreamController<String>.broadcast();
  bool started = false;
  bool stopped = false;

  void emit(String code) => _codes.add(code);

  @override
  Stream<String> get codes => _codes.stream;

  @override
  Future<String?> start() async {
    started = true;
    return null;
  }

  @override
  Widget view() => const SizedBox.shrink();

  @override
  void stop() {
    stopped = true;
    unawaited(_codes.close());
  }
}

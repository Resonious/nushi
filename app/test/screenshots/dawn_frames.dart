// Frames of the app's start, for a video: the daemon starting (the
// drop's rings), then up (the sweep, the app clearing into place). Not
// run by `make test`. Run with:
//   POND_FRAMES=/tmp/frames flutter test test/screenshots/dawn_frames.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/main.dart';
import 'package:nushi/native.dart';
import 'package:nushi/pond.dart';
import 'package:nushi/settings.dart';

import '../fake_app_install.dart';
import '../fake_daemon.dart';
import '../harness.dart';

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

final Chat _chat = chat('a', 'claude', 'Fix the login redirect loop');

void main() {
  setUpAll(loadFonts);

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('dawn frames ${brightness.name}', (tester) async {
      viewport(tester, const Size(1280, 800), brightness: brightness);
      showDetails.value = true;
      // Installed, so it's starting rather than missing.
      final install = native.install as FakeAppInstall;
      final had = install.daemon;
      install.daemon = '/Applications/Nushi.app/nushid';
      addTearDown(() => install.daemon = had);
      final fake = FakeDaemon([_chat])
        ..down = true
        ..answer = (input) => switch (input) {
          GetChatRequest() => GetChatResponse(
            chat: _chat,
            items: [
              Item(
                id: 'u1',
                kind: ItemKind.ITEM_KIND_USER_MESSAGE,
                text: 'Why do uploads log people out?',
              ),
              Item(
                id: 'm1',
                kind: ItemKind.ITEM_KIND_AGENT_MESSAGE,
                text: 'The session cookie expires mid-upload. I refresh it '
                    'before a long upload starts now; `npm test` passes.',
              ),
            ],
            status: ChatStatus(),
          ),
          _ => null,
        };
      final d = await fake.connect(tester);
      d.select('a');
      await tester.runAsync(Pond.load);
      await tester.pumpWidget(NushiApp(daemon: d));
      debugDisableShadows = false;
      final dir = Directory(
        '${Platform.environment['POND_FRAMES']}/dawn-${brightness.name}',
      )..createSync(recursive: true);
      var n = 0;
      Future<void> frame() async {
        final capture = captureImage(find.byType(NushiApp).evaluate().single);
        await tester.runAsync(() async {
          final ui.Image image = await capture;
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${dir.path}/${(n++).toString().padLeft(4, '0')}.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }

      const step = Duration(microseconds: 16667);
      Future<void> frames(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.pump(step);
          await frame();
        }
      }

      await frames(150);
      fake.down = false;
      // Until it's up, then the app's coming.
      for (var i = 0; i < 400 && !d.connected; i++) {
        await frames(1);
      }
      await frames(110);
      debugDisableShadows = true;
      await closeView(tester, d);
    }, variant: _mac);
  }
}

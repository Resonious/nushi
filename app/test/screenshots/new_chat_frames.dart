// Frames of starting a new chat, for a video: ⌘N, the agent picked, the
// daemon starting it (slowly, as a real agent does), then the empty chat.
// Not run by `make test`. Run with:
//   POND_FRAMES=/tmp/frames flutter test test/screenshots/new_chat_frames.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/main.dart';
import 'package:nushi/pond.dart';
import 'package:nushi/settings.dart';

import '../fake_daemon.dart';
import '../harness.dart';

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

final Chat _chat = chat('a', 'claude', 'Fix the login redirect loop');

final _items = [
  Item(
    id: 'u1',
    kind: ItemKind.ITEM_KIND_USER_MESSAGE,
    text:
        'Users get bounced back to the login page after uploading a '
        'large file. Can you find out why?',
  ),
  Item(
    id: 'm1',
    kind: ItemKind.ITEM_KIND_AGENT_MESSAGE,
    text:
        'The session cookie expires mid-upload. I refresh it before a '
        'long upload starts now; `npm test` passes.',
  ),
];

void main() {
  setUpAll(loadFonts);

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('new chat frames ${brightness.name}', (tester) async {
      viewport(tester, const Size(1280, 800), brightness: brightness);
      showDetails.value = Platform.environment["DETAILS"] == "1" ? true : false;
      final fresh = chat('n', 'claude', '', age: -1);
      late FakeDaemon fake;
      fake = FakeDaemon([_chat])
        ..answer = (input) => switch (input) {
          GetChatRequest(chatId: 'a') => GetChatResponse(
            chat: _chat,
            items: _items,
            status: ChatStatus(),
          ),
          // Its items come a moment after it's shown, as a real
          // daemon's do.
          GetChatRequest(chatId: 'n') => Future.delayed(
            const Duration(milliseconds: 400),
            () => GetChatResponse(chat: fresh, status: ChatStatus()),
          ),
          // A real agent takes a while to start.
          StartChatRequest() => Future.delayed(
            const Duration(milliseconds: 1500),
            () {
              fake.chats.add(fresh);
              fake.emit(EventsResponse(chatId: 'n', chat: fresh));
              return StartChatResponse(chatId: 'n');
            },
          ),
          _ => null,
        };
      final d = await fake.connect(tester);
      if (Platform.environment['FRESH'] != '1') d.select('a');
      await tester.runAsync(Pond.load);
      await tester.pumpWidget(NushiApp(daemon: d));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      debugDisableShadows = false;
      final dir = Directory(
        '${Platform.environment['POND_FRAMES']}/new-${brightness.name}',
      )..createSync(recursive: true);
      var n = 0;
      Future<void> frame() async {
        final capture = captureImage(find.byType(NushiApp).evaluate().single);
        await tester.runAsync(() async {
          final ui.Image image = await capture;
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/${(n++).toString().padLeft(4, '0')}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
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

      await frames(15);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await frames(40);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await frames(90); // starting
      await frames(150); // started
      await tester.enterText(find.byType(TextField).last, 'Add a dark mode');
      await frames(30);
      debugDisableShadows = true;
      await closeView(tester, d);
    }, variant: _mac);
  }
}

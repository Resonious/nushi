// Frames of the pond's effects, for a video: the real app on a fake daemon,
// a PNG every 1/60 s. A message sent (the ripple, then the glint), a long
// turn (caustics, surfacing words, the koi's leap), then a short one (a
// message's ripple and the firefly). Not run by `make test` (the name
// doesn't end in _test.dart). Run with:
//   POND_FRAMES=/tmp/frames flutter test test/screenshots/pond_frames.dart
// then, for example:
//   ffmpeg -framerate 60 -i /tmp/frames/dark/%04d.png pond.mp4
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/clock.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/main.dart';
import 'package:nushi/pond.dart';
import 'package:nushi/settings.dart';

import '../fake_daemon.dart';
import '../harness.dart';

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

final Chat _chat = chat('a', 'claude', 'Fix the login redirect loop');

const _reply = '''
The loop comes from the session cookie expiring mid-upload. When the
upload finishes, `requireAuth` sees no session and redirects to `/login`,
which redirects back to the upload page once it finds the refresh token.

The fix is to refresh the session *before* a long upload starts:

```ts
export async function beginUpload(file: File) {
  await session.refreshIfOlderThan(minutes(5));
  return uploads.start(file, { onProgress: track });
}
```

I also added a guard so `/login` never redirects to a page that itself
requires a fresh session. Both changes are in `src/auth/session.ts`, and
`npm test` passes: 148 tests, 0 failures.
''';

final _items = [
  Item(
    id: 'u1',
    kind: ItemKind.ITEM_KIND_USER_MESSAGE,
    text: 'Users get bounced back to the login page after uploading a '
        'large file. Can you find out why?',
  ),
  Item(id: 'm1', kind: ItemKind.ITEM_KIND_AGENT_MESSAGE, text: _reply),
];

const _thanks = 'Perfect, thanks!';

const _welcome = 'Glad it helps. Ping me if the upload test is ever flaky.';

const _sent = 'Nice. Can you add a test that uploads for six minutes?';

const _answer = '''
Sure. A six-minute upload is too slow for the suite, so the test fakes the
clock instead: it starts an upload, moves time past the session's lifetime,
then finishes the upload and checks that nobody gets bounced to the login
page.

```ts
it('keeps the session through a long upload', async () => {
  const clock = fakeClock();
  await beginUpload(bigFile);
  clock.advance(minutes(6));
  expect(await finishUpload()).toBe('ok');
});
```

I put it next to the other session tests in `src/auth/session.test.ts`.
It fails on the old code and passes with the fix, so it guards exactly the
bug you saw.
''';

EventsResponse _event(
  int seq,
  Item item, {
  bool append = false,
  int index = 3,
}) =>
    EventsResponse(
      chatId: 'a',
      seq: Int64(seq),
      item: ItemEvent(item: item, append: append, index: append ? 0 : index),
    );

void main() {
  setUpAll(loadFonts);

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('pond frames ${brightness.name}', (tester) async {
      viewport(tester, const Size(1280, 800), brightness: brightness);
      showDetails.value = false;
      final fake = FakeDaemon([_chat])
        ..answer = (input) => switch (input) {
          GetChatRequest() => GetChatResponse(
            chat: _chat,
            items: _items,
            status: ChatStatus(),
          ),
          SendPromptRequest() => SendPromptResponse(),
          _ => null,
        };
      final d = await fake.connect(tester);
      d.select('a');
      await tester.runAsync(Pond.load);
      await tester.pumpWidget(NushiApp(daemon: d));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      debugDisableShadows = false;
      final dir = Directory(
        '${Platform.environment['POND_FRAMES']}/${brightness.name}',
      )..createSync(recursive: true);
      var n = 0;
      Future<void> frame() async {
        final capture = captureImage(
          find.byType(NushiApp).evaluate().single,
        );
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
      await tester.enterText(find.byType(TextField).last, _sent);
      for (var i = 0; i < 24; i++) {
        await tester.pump(step);
        await frame();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      for (var i = 0; i < 30; i++) {
        await tester.pump(step);
        await frame();
      }
      fake
        ..emit(
          _event(
            1,
            Item(
              id: 'u2',
              kind: ItemKind.ITEM_KIND_USER_MESSAGE,
              text: _sent,
            ),
          )..item.index = 2,
        )
        ..emit(
          EventsResponse(
            chatId: 'a',
            seq: Int64(2),
            status: ChatStatus(
              busy: true,
              started: Int64(
                clock().millisecondsSinceEpoch - 2 * 60 * 1000,
              ),
            ),
          ),
        );
      for (var i = 0; i < 100; i++) {
        await tester.pump(step);
        await frame();
      }
      var seq = 3;
      var at = 0;
      var first = true;
      var tick = 0;
      while (at < _answer.length) {
        if (tick++ % 3 == 0) {
          final n = 9 + (tick * 7) % 11;
          final chunk = _answer.substring(at, (at + n).clamp(0, _answer.length));
          at += chunk.length;
          fake.emit(
            _event(
              seq++,
              Item(
                id: 'm2',
                kind: ItemKind.ITEM_KIND_AGENT_MESSAGE,
                text: chunk,
              ),
              append: !first,
            ),
          );
          first = false;
        }
        await tester.pump(step);
        await frame();
      }
      fake.emit(
        EventsResponse(chatId: 'a', seq: Int64(seq++), status: ChatStatus()),
      );
      for (var i = 0; i < 170; i++) {
        await tester.pump(step);
        await frame();
      }

      // A short turn: thanks, and a quick answer. Its end sends a firefly.
      await tester.enterText(find.byType(TextField).last, _thanks);
      for (var i = 0; i < 12; i++) {
        await tester.pump(step);
        await frame();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      for (var i = 0; i < 20; i++) {
        await tester.pump(step);
        await frame();
      }
      fake
        ..emit(
          _event(
            seq++,
            Item(
              id: 'u3',
              kind: ItemKind.ITEM_KIND_USER_MESSAGE,
              text: _thanks,
            ),
            index: 4,
          ),
        )
        ..emit(
          EventsResponse(
            chatId: 'a',
            seq: Int64(seq++),
            status: ChatStatus(
              busy: true,
              started: Int64(clock().millisecondsSinceEpoch),
            ),
          ),
        );
      for (var i = 0; i < 30; i++) {
        await tester.pump(step);
        await frame();
      }
      at = 0;
      first = true;
      tick = 0;
      while (at < _welcome.length) {
        if (tick++ % 3 == 0) {
          final n = 9 + (tick * 7) % 11;
          final chunk = _welcome.substring(
            at,
            (at + n).clamp(0, _welcome.length),
          );
          at += chunk.length;
          fake.emit(
            _event(
              seq++,
              Item(
                id: 'm3',
                kind: ItemKind.ITEM_KIND_AGENT_MESSAGE,
                text: chunk,
              ),
              append: !first,
              index: 5,
            ),
          );
          first = false;
        }
        await tester.pump(step);
        await frame();
      }
      fake.emit(
        EventsResponse(chatId: 'a', seq: Int64(seq++), status: ChatStatus()),
      );
      for (var i = 0; i < 110; i++) {
        await tester.pump(step);
        await frame();
      }
      debugDisableShadows = true;
      await closeView(tester, d);
    }, variant: _mac);

    testWidgets('pond splash ${brightness.name}', (tester) async {
      viewport(tester, const Size(1280, 800), brightness: brightness);
      showDetails.value = false;
      final all = [
        ..._items,
        Item(id: 'u2', kind: ItemKind.ITEM_KIND_USER_MESSAGE, text: _sent),
        Item(id: 'm2', kind: ItemKind.ITEM_KIND_AGENT_MESSAGE, text: _answer),
        Item(id: 'u3', kind: ItemKind.ITEM_KIND_USER_MESSAGE, text: _thanks),
        Item(id: 'm3', kind: ItemKind.ITEM_KIND_AGENT_MESSAGE, text: _welcome),
      ];
      final fake = FakeDaemon([_chat])
        ..answer = (input) => switch (input) {
          GetChatRequest() => GetChatResponse(
            chat: _chat,
            items: all,
            status: ChatStatus(),
          ),
          _ => null,
        };
      final d = await fake.connect(tester);
      d.select('a');
      await tester.runAsync(Pond.load);
      await tester.pumpWidget(NushiApp(daemon: d));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      debugDisableShadows = false;
      final dir = Directory(
        '${Platform.environment['POND_FRAMES']}/splash-${brightness.name}',
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

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(700, 300)));
      Future<void> wheel(double dy) async {
        await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
        await tester.pump(step);
        await frame();
      }

      await frames(15);
      // Up a way, then a quick spin back down: it lands hard.
      for (var i = 0; i < 8; i++) {
        await wheel(-70);
      }
      await frames(30);
      for (var i = 0; i < 12; i++) {
        await wheel(150);
      }
      await frames(80);
      // Up again, slowly down to the end: a soft landing.
      for (var i = 0; i < 4; i++) {
        await wheel(-60);
      }
      await frames(25);
      for (var i = 0; i < 30; i++) {
        await wheel(12);
      }
      await frames(70);
      // Up again, and Jump to latest glides it home.
      for (var i = 0; i < 8; i++) {
        await wheel(-70);
      }
      await frames(30);
      await tester.tap(find.text('Jump to latest'));
      await frames(100);
      debugDisableShadows = true;
      await closeView(tester, d);
    }, variant: _mac);
  }
}

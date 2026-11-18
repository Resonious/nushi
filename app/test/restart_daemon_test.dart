import 'dart:async';

import 'package:connectrpc/connect.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';

import 'fake_app_install.dart';
import 'fake_daemon.dart';

/// Until [d] has answered its first ping (10 s at most).
Future<void> _connected(Daemon d) async {
  for (var i = 0; !d.connected; i++) {
    if (i == 1000) fail('never connected');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('a restart returns once the new daemon answers', () async {
    var phase = 'old'; // then 'gone', then 'new'
    final fake = FakeDaemon([])
      ..answer = (input) => switch (input) {
        PingRequest() when phase == 'gone' => throw ConnectException(
          Code.unavailable,
          'no daemon',
        ),
        PingRequest() => PingResponse(apiVersion: apiVersion, build: phase),
        _ => null,
      };
    final d = Daemon(transport: fake);
    addTearDown(d.dispose);
    await _connected(d);
    expect(d.connected, isTrue);

    // It goes, then the new one comes a moment later.
    Future<void>.delayed(
      const Duration(milliseconds: 100),
      () => phase = 'gone',
    );
    Future<void>.delayed(
      const Duration(milliseconds: 900),
      () => phase = 'new',
    );
    await d.restartDaemon();
    expect((d.connected, phase), (true, 'new'));
  });

  test('a restart stops the daemon of the data folder, by the pid it '
      'says just then, and starts the packaged one once it has gone', () async {
    fakeInstall.daemon = '/opt/nushi/lib/nushid';
    var phase = 'old';
    var pid = 4242;
    final fake = FakeDaemon([])
      ..answer = (input) => switch (input) {
        PingRequest() when phase == 'gone' => throw ConnectException(
          Code.unavailable,
          'no daemon',
        ),
        PingRequest() => PingResponse(
          apiVersion: apiVersion,
          build: phase,
          pid: pid,
        ),
        _ => null,
      };
    final d = Daemon(transport: fake);
    addTearDown(d.dispose);
    await _connected(d);
    // It restarted itself since the last ping: the pid that ping gave
    // names no daemon now.
    pid = 5151;
    Future<void>.delayed(
      const Duration(milliseconds: 100),
      () => phase = 'gone',
    );
    Future<void>.delayed(
      const Duration(milliseconds: 600),
      () => phase = 'new',
    );
    await d.restartDaemon();
    expect(fakeInstall.stopped, [dataDir]);
    expect(fakeInstall.stoppedPids, [5151]);
    expect(fakeInstall.launched, [dataDir]);
  });

  // Ten seconds of tries, on the test's clock rather than waited out.
  testWidgets('a daemon that never stops is said, not waited on quietly', (
    tester,
  ) async {
    final fake = FakeDaemon([])
      ..answer = (input) => input is PingRequest
          ? PingResponse(apiVersion: apiVersion, build: 'old')
          : null;
    final d = Daemon(transport: fake);
    await tester.pump(const Duration(milliseconds: 50));
    expect(d.connected, isTrue);
    Object? error;
    var done = false;
    unawaited(
      d.restartDaemon().then(
        (_) => done = true,
        onError: (Object e) => error = e,
      ),
    );
    await tester.pump(const Duration(seconds: 9));
    expect((done, error), (false, null)); // still trying
    await tester.pump(const Duration(seconds: 2));
    expect(error, isA<StateError>());
    d.dispose();
  });

  // As above, but the daemon restarted itself into a newer build since the
  // last ping: the build it's compared with is the one just before the
  // stop, so a stop that did nothing is still said.
  testWidgets('a daemon that restarted itself and then never stops is said', (
    tester,
  ) async {
    var build = 'old';
    final fake = FakeDaemon([])
      ..answer = (input) => input is PingRequest
          ? PingResponse(apiVersion: apiVersion, build: build, pid: 7)
          : null;
    final d = Daemon(transport: fake);
    await tester.pump(const Duration(milliseconds: 50));
    expect(d.connected, isTrue);
    build = 'newer';
    Object? error;
    unawaited(d.restartDaemon().then((_) {}, onError: (Object e) => error = e));
    await tester.pump(const Duration(seconds: 11));
    expect(error, isA<StateError>());
    d.dispose();
  });

  test("a failed ping forgets the daemon's pid", () async {
    var up = true;
    final fake = FakeDaemon([])
      ..answer = (input) => switch (input) {
        PingRequest() when !up => throw ConnectException(
          Code.unavailable,
          'no daemon',
        ),
        PingRequest() => PingResponse(apiVersion: apiVersion, pid: 4242),
        _ => null,
      };
    final d = Daemon(transport: fake);
    addTearDown(d.dispose);
    await _connected(d);
    expect(d.daemonPid, 4242);
    up = false;
    expect(await d.ping(), isFalse);
    expect(d.daemonPid, 0);
  });

  test(
    'one restart at a time: a second asked meanwhile is the same one',
    () async {
      var phase = 'old';
      final fake = FakeDaemon([])
        ..answer = (input) => switch (input) {
          PingRequest() when phase == 'gone' => throw ConnectException(
            Code.unavailable,
            'no daemon',
          ),
          PingRequest() => PingResponse(apiVersion: apiVersion, build: phase),
          _ => null,
        };
      final d = Daemon(transport: fake);
      addTearDown(d.dispose);
      await _connected(d);
      Future<void>.delayed(
        const Duration(milliseconds: 100),
        () => phase = 'gone',
      );
      Future<void>.delayed(
        const Duration(milliseconds: 900),
        () => phase = 'new',
      );
      final first = d.restartDaemon();
      expect(d.restarting, isTrue);
      // A second stop would stop the daemon the first one started.
      expect(d.restartDaemon(), same(first));
      await first;
      expect((d.restarting, d.connected, phase), (false, true, 'new'));
    },
  );

  test(
    'one ping at a time: a ping asked while one is out gets its answer',
    () async {
      final answer = Completer<PingResponse>();
      final fake = FakeDaemon([])
        ..answer = (input) => input is PingRequest ? answer.future : null;
      final d = Daemon(transport: fake); // its first ping is out
      addTearDown(d.dispose);
      final again = d.ping();
      answer.complete(PingResponse(apiVersion: apiVersion));
      expect(await again, isTrue);
      expect(fake.calls.whereType<PingRequest>(), hasLength(1));
    },
  );
}

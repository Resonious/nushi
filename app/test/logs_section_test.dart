import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/app_actions.dart';
import 'package:nushi/bundled_daemon.dart';
import 'package:nushi/controls.dart' show Toggle;
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/logs_section.dart';

import 'fake_app_install.dart';
import 'fake_daemon.dart';
import 'harness.dart';
import 'settings_harness.dart';

Future<Daemon> _section(
  WidgetTester tester, {
  required bool? debug,
  required Future<void> Function({required bool on}) onDebug,
  required Future<void> Function() reveal,
}) async {
  final d = await FakeDaemon([]).connect(tester);
  await tester.pumpWidget(
    themed(
      LogsSection(daemon: d, debug: debug, onDebug: onDebug, reveal: reveal),
    ),
  );
  return d;
}

void main() {
  test("a daemon build's time", () {
    expect(buildTime('1234-1761555000000'), isNotNull);
    expect(
      buildTime('1234-1761555000000')!.millisecondsSinceEpoch,
      1761555000000,
    );
    expect(buildTime(''), isNull);
    expect(buildTime('garbage'), isNull);
  });

  testWidgets('Show logs reveals them; the switch sets debug lines', (
    tester,
  ) async {
    var revealed = 0;
    final set = <bool>[];
    final d = await _section(
      tester,
      debug: false,
      onDebug: ({required on}) async => set.add(on),
      reveal: () async => revealed++,
    );
    await tester.tap(find.text('Show logs'));
    await tester.tap(find.byType(Toggle));
    expect(revealed, 1);
    expect(set, [true]);
    expect(find.text('Debug lines'), findsOneWidget);
    expect(find.text('API $apiVersion'), findsOneWidget);
    d.dispose();
  });

  testWidgets('the debug switch sends once, however often it is clicked', (
    tester,
  ) async {
    final sent = Completer<void>();
    var calls = 0;
    final d = await _section(
      tester,
      debug: false,
      onDebug: ({required on}) {
        calls++;
        return sent.future;
      },
      reveal: () async {},
    );
    await tester.tap(find.byType(Toggle));
    await tester.pump();
    await tester.tap(find.byType(Toggle));
    await tester.pump();
    expect(calls, 1);
    sent.complete();
    await tester.pump();
    d.dispose();
  });

  testWidgets("a packaged daemon's release shows beside its API", (
    tester,
  ) async {
    final fake = FakeDaemon([])
      ..answer = (r) => r is PingRequest
          ? PingResponse(apiVersion: apiVersion, version: '1.2.0')
          : null;
    final d = await fake.connect(tester);
    await tester.pumpWidget(
      themed(
        LogsSection(daemon: d, debug: null, onDebug: ({required on}) async {}),
      ),
    );
    expect(find.text('Version 1.2.0 · API $apiVersion'), findsOneWidget);
    d.dispose();
  });

  testWidgets('Restart shows for a packaged daemon, and not without one: '
      'here nor in the palette', (tester) async {
    fakeInstall.daemon = '/opt/nushi/lib/nushid';
    final d = await FakeDaemon([]).connect(tester);
    late BuildContext context;
    Future<void> show() async {
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (c) {
              context = c;
              return LogsSection(
                daemon: d,
                debug: null,
                onDebug: ({required on}) async {},
              );
            },
          ),
        ),
      );
      await tester.pump();
    }

    bool restartRow() =>
        appActions(context, d).any((a) => a.act == Act.restart && a.enabled);

    await show();
    expect(find.text('Restart'), findsOneWidget);
    expect(restartRow(), isTrue);
    fakeInstall.daemon = null;
    await show();
    expect(find.text('Restart'), findsNothing);
    expect(restartRow(), isFalse);
    d.dispose();
  });

  testWidgets('no switch until the daemon says', (tester) async {
    final d = await _section(
      tester,
      debug: null,
      onDebug: ({required on}) async {},
      reveal: () async {},
    );
    expect(find.text('Show logs'), findsOneWidget);
    expect(find.byType(Toggle), findsNothing);
    d.dispose();
  });

  testWidgets('Settings sets debug lines and keeps the sleep time', (
    tester,
  ) async {
    final fake = FakeDaemon([])
      ..settings = Settings(sleepAfterMinutes: 60, debugLog: false);
    final d = await fake.connect(tester);
    await pumpSettings(tester, d, SettingsSection.logs);
    await tester.tap(find.byType(Toggle));
    await tester.pumpAndSettle();
    expect(fake.setSettings.single.debugLog, isTrue);
    expect(fake.setSettings.single.sleepAfterMinutes, 60);
    d.dispose();
  });
}

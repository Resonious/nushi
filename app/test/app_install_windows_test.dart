import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/app_install_windows.dart';

void main() {
  test('what the daemon says on stderr is read whole, trimmed', () async {
    final why = utf8.encode('nushid can’t run: nd belongs to X\n');
    expect(
      await daemonSaid(
        Stream.fromIterable([why.sublist(0, 9), why.sublist(9)]),
      ),
      'nushid can’t run: nd belongs to X',
    );
    expect(await daemonSaid(const Stream.empty()), '');
  });

  test('a daemon that goes on writing is read no further', () async {
    final err = StreamController<List<int>>();
    addTearDown(err.close);
    var cancelled = false;
    err.onCancel = () => cancelled = true;
    final said = daemonSaid(err.stream);
    err.add(List.filled(5000, 0x61));
    expect((await said).length, 5000);
    expect(cancelled, isTrue);
  });

  test("stop sets the daemon's stop event, named by the pid it said; "
      'without a pid nothing is set', () async {
    final set = <String>[];
    final install = WindowsAppInstall(
      executable: r'C:\Nushi\nushi.exe',
      environment: const {},
      setEvent: (name) {
        set.add(name);
        return true;
      },
    );
    expect(install.canStop, isTrue);
    await install.stop(r'C:\nd', pid: 4242);
    await install.stop(r'C:\nd');
    expect(set, [r'Local\nushid-4242-stop']);
  });

  test(
    'an event that no process made is not set',
    () => expect(setNamedEvent(stopEventName(0x7ffffff0)), isFalse),
    skip: !Platform.isWindows,
  );
}

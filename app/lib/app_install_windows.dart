import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:nushi/app_install.dart';
import 'package:nushi/app_log.dart';

/// Windows's install (ADR 0125): `nushi.exe` with the daemon,
/// `nushid.exe`, beside it, the version Flutter writes into
/// `data\flutter_assets\version.json`, and the data folder nushid picks
/// itself (ADR 0124). The daemon starts on its own, with the app's
/// environment and no login shell (Windows has none to start it
/// through), and logs to its folder itself; it stops by its stop event
/// (ADR 0134).
class WindowsAppInstall implements AppInstall {
  /// A test passes the [executable] the app runs as, its [environment],
  /// and what sets a named event in [setEvent].
  new({
    String? executable,
    Map<String, String>? environment,
    this.setEvent = setNamedEvent,
  }) : _bundle = File(executable ?? Platform.resolvedExecutable).parent.path,
       _env = environment ?? Platform.environment;

  final String _bundle;
  final Map<String, String> _env;

  /// What sets the event of a name, saying whether there was one.
  final bool Function(String name) setEvent;

  /// `%LOCALAPPDATA%\Nushi`, else under the home's `AppData\Local`:
  /// nushid's own rule.
  @override
  String get dataFolder => switch (_env['LOCALAPPDATA']) {
    final local? when local.contains(':') => '$local\\Nushi',
    _ => '${_env['USERPROFILE']}\\AppData\\Local\\Nushi',
  };

  @override
  late final String? daemon = () {
    final path = '$_bundle\\nushid.exe';
    return File(path).existsSync() ? path : null;
  }();

  @override
  late final String? daemonBuild = () {
    if (daemon case final path?) {
      final st = File(path).statSync();
      return '${st.size}-${st.modified.millisecondsSinceEpoch}';
    }
    return null;
  }();

  /// The build's `version` and `build_number`, as Linux's.
  @override
  late final String version = () {
    try {
      final json = jsonDecode(
        File('$_bundle\\data\\flutter_assets\\version.json').readAsStringSync(),
      ) as Map<String, Object?>;
      return '${json['version'] ?? ''}+${json['build_number'] ?? ''}';
    } on Object {
      return '';
    }
  }();

  @override
  String get stopByHand => 'end nushid.exe in Task Manager';

  @override
  bool get canStop => true;

  /// Started detached with its standard streams, so what it says on
  /// stderr goes to the app's log: a daemon whose data folder isn't the
  /// user's alone says there why it won't run, before it has a log of its
  /// own (ADR 0124). One that starts says nothing: it starts itself again
  /// with no window, its stderr `nushid.log`, and exits.
  @override
  Future<void> launch(String dataDir) async {
    final program = daemon;
    if (program == null) return;
    final Process started;
    try {
      started = await Process.start(
        program,
        const [],
        environment: launchEnvironment(_env, dataDir),
        includeParentEnvironment: false,
        mode: ProcessStartMode.detachedWithStdio,
      );
    } on ProcessException catch (e) {
      appLog.warn("the bundled daemon didn't start", {'error': e.message});
      return;
    }
    started.stdin.close().ignore();
    started.stdout.drain<void>().ignore();
    final said = await daemonSaid(started.stderr);
    if (said.isNotEmpty) {
      appLog.warn('the bundled daemon said, starting', {'stderr': said});
    }
  }

  /// By the daemon's stop event, named by the [pid] its Ping said (ADR
  /// 0134): Windows doesn't name a Unix socket's other end, and a process
  /// with no console window has no SIGTERM. The daemon stops as it does
  /// on one (its agents and terminals closed first). One too old to say
  /// its pid, or one gone, isn't stopped, and the restart that asked says
  /// how to end it by hand.
  @override
  Future<void> stop(String dataDir, {int pid = 0}) async {
    if (pid <= 0) {
      appLog.warn("the daemon didn't say its pid, so none was stopped");
      return;
    }
    if (!setEvent(stopEventName(pid))) {
      appLog.warn('the daemon had no stop event', {'pid': '$pid'});
      return;
    }
    appLog.info('the daemon was asked to stop', {'pid': '$pid'});
  }
}

/// The stop event of the daemon whose process is [pid], in the session's
/// own namespace, as the daemon names it (`cmd/nushid/stopevent_windows.go`).
String stopEventName(int pid) =>
    r'Local\nushid-'
    '$pid-stop';

/// Sets the event named [name], if there's one this user may set: whether
/// it was set.
bool setNamedEvent(String name) {
  if (!_kernel32.providesSymbol('OpenEventW')) return false;
  final wide = Uint16List.fromList([...name.codeUnits, 0]);
  final event = _openEvent(_eventModifyState, 0, wide.address);
  if (event == nullptr) return false;
  try {
    return _setEvent(event) != 0;
  } finally {
    _closeHandle(event);
  }
}

/// EVENT_MODIFY_STATE: the right to set an event, and nothing else.
const _eventModifyState = 0x2;

/// kernel32, loaded before the first call, so the process's lookup of the
/// calls below finds it.
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

@Native<Pointer<Void> Function(Uint32, Int32, Pointer<Uint16>)>(
  symbol: 'OpenEventW',
  isLeaf: true,
)
external Pointer<Void> _openEvent(
  int access,
  int inherit,
  Pointer<Uint16> name,
);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'SetEvent', isLeaf: true)
external int _setEvent(Pointer<Void> event);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'CloseHandle', isLeaf: true)
external int _closeHandle(Pointer<Void> handle);

/// The first of what [stderr] says, trimmed: at most about 4 KB, after
/// which it's no longer read, so a daemon that goes on writing there
/// fills nothing.
Future<String> daemonSaid(Stream<List<int>> stderr) async {
  final said = StringBuffer();
  await for (final text in const Utf8Decoder(
    allowMalformed: true,
  ).bind(stderr)) {
    said.write(text);
    if (said.length >= 4096) break;
  }
  return said.toString().trim();
}

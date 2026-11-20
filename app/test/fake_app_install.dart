import 'package:nushi/app_install.dart';
import 'package:nushi/native.dart';

/// The installed app as a test has it, in the Mac's place: no packaged
/// daemon unless the test gives one, and what it was asked to start and
/// stop, never a process.
class FakeAppInstall implements AppInstall {
  @override
  String get dataFolder => '/nushi-test-no-data-folder';

  @override
  String? daemon;

  @override
  String? daemonBuild;

  @override
  String version = '';

  @override
  String get stopByHand => 'quit nushid in Activity Monitor';

  /// The data folders it was asked to start a daemon on, in order.
  final launched = <String>[];

  /// The data folders it was asked to stop the daemon of, in order.
  final stopped = <String>[];

  /// The pids it was given with each stop, in order.
  final stoppedPids = <int>[];

  @override
  Future<void> launch(String dataDir) async => launched.add(dataDir);

  @override
  Future<void> stop(String dataDir, {int pid = 0}) async {
    stopped.add(dataDir);
    stoppedPids.add(pid);
  }
}

/// The test's [FakeAppInstall] (`flutter_test_config.dart` puts one in
/// place for each test).
FakeAppInstall get fakeInstall => native.install as FakeAppInstall;

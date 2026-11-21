import 'package:connectrpc/connect.dart';
import 'package:flutter/foundation.dart';
import 'package:nushi/errors.dart';
import 'package:nushi/gen/nushi/v1/nushi.connect.client.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';

/// The ways a refused start says its agent signs itself in ([AgentSignIn],
/// API 139, ADR 0145): the detail of [e], a start the agent refused for want
/// of a sign-in Nushi can run; null for any other error, and for a daemon
/// older than sign-ins.
AgentSignIn? agentSignIn(Object e) {
  if (e is! ConnectException) return null;
  for (final d in e.details) {
    if (d.type == AgentSignIn().info_.qualifiedMessageName ||
        d.type.endsWith('/${AgentSignIn().info_.qualifiedMessageName}')) {
      try {
        final s = AgentSignIn.fromBuffer(d.value);
        if (s.methods.isNotEmpty) return s;
      } on Object {
        return null; // not one this app reads
      }
    }
  }
  return null;
}

/// An agent's sign-in through its own login (SignInAgent): one at a time
/// for each agent, as the daemon runs them, kept by the daemon's state
/// (`Daemon.signIns`) so the card and the dialog showing it share it and
/// it outlives either. [waiting] while the agent waits on the browser,
/// [failed] once the last one didn't finish.
class SignInRun extends ChangeNotifier {
  new(this._client, this.agent);

  final NushiServiceClient _client;

  /// The agent's name.
  final String agent;

  /// The method running, while one is.
  String? waiting;

  /// Why the last one didn't finish, in the agent's words; null after one
  /// that did, or was cancelled.
  String? failed;

  /// How many of its sign-ins ended signed in: what tells a dialog that
  /// didn't start the one running (a card did) that it worked.
  int signedIn = 0;

  CancelableSignal? _signal;

  /// The sign-in running, to tell it from another; null while none runs.
  Object? get running => _signal;

  /// Signs the agent in through [method]: true once the agent says it is,
  /// false when it didn't (see [failed]), was cancelled, or one runs
  /// already.
  Future<bool> start(String method) async {
    if (waiting != null) return false;
    final signal = _signal = CancelableSignal();
    waiting = method;
    failed = null;
    notifyListeners();
    try {
      await _client.signInAgent(
        SignInAgentRequest(agent: agent, methodId: method),
        signal: signal,
      );
      signedIn++;
      return true;
    } on Object catch (e) {
      final cancelled = e is ConnectException && e.code == Code.canceled;
      failed = cancelled ? null : errorText(e);
      return false;
    } finally {
      _signal = null;
      waiting = null;
      notifyListeners();
    }
  }

  /// Forgets why the last one failed, unless one runs: a new refusal
  /// starts afresh, and the user may have signed in elsewhere since.
  void forget() {
    if (waiting != null || failed == null) return;
    failed = null;
    notifyListeners();
  }

  /// Gives up on the one running: the daemon stops the agent's login.
  void cancel() => _signal?.cancel();
}

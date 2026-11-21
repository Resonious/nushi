import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nushi/agents.dart';
import 'package:nushi/cards.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/sign_in_run.dart';
import 'package:nushi/spinner.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/widgets.dart';

export 'package:nushi/sign_in_run.dart' show agentSignIn;

/// Runs [start], a chat's start; when its agent refuses it
/// for want of a sign-in Nushi can run ([agentSignIn]), offers to sign it
/// in ([signInDialog]) and, signed in, starts again, as many times as it
/// takes. Any other error is [tryOrShow]'s toast; a sign-in given up on
/// shows nothing more (the agent stays marked as not started).
Future<void> startSigningIn(
  BuildContext context,
  Daemon daemon,
  Future<void> Function() start,
) => tryOrShow(context, () async {
  while (true) {
    try {
      return await start();
    } on Object catch (e) {
      final s = agentSignIn(e);
      if (s == null || !context.mounted) rethrow;
      if (!await signInDialog(context, daemon, s) || !context.mounted) return;
    }
  }
});

/// Asks to sign in [s]'s agent before a chat starts (ADR 0145): its card
/// in a dialog; true once the agent says it's signed in, false when the
/// user closed it (a sign-in running is cancelled then).
Future<bool> signInDialog(
  BuildContext context,
  Daemon daemon,
  AgentSignIn s,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _SignInDialog(daemon.signInOf(s.agent), s.methods),
    ) ??
    false;

class _SignInDialog extends StatelessWidget {
  const new(this.run, this.methods);

  final SignInRun run;
  final List<Option> methods;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: run,
    builder: (context, _) => PopScope(
      onPopInvokedWithResult: (popped, _) {
        if (popped) run.cancel(); // Esc while waiting: the login ends
      },
      child: nushiDialog(
        signInTitle(run.agent),
        SignInLines(run, starts: true),
        signInButtons(
          run,
          methods,
          onCancel: () => Navigator.pop(context, false),
          onSignedIn: () => Navigator.pop(context, true),
        ),
      ),
    ),
  );
}

/// The card in a chat's transcript where its reopen failed because its
/// agent isn't signed in ([item], a notice of status "sign_in" whose options
/// are the ways to sign in): signed in, the chat reopens, and a message
/// waiting goes (ADR 0145).
class SignInCard extends StatelessWidget {
  const new(this.item, this.chat, this.daemon, {super.key});

  final Item item;
  final ChatState chat;
  final Daemon daemon;

  @override
  Widget build(BuildContext context) {
    final run = daemon.signInOf(chat.agent);
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) => WaitingCard(
        waiting: true,
        children: [
          CardTitle(signInTitle(chat.agent)),
          SignInLines(run, starts: false, status: false),
          // Where it is at the row's start, the buttons at its end: the
          // one pressed stays put.
          Row(
            spacing: 8,
            children: [
              Expanded(child: SignInStatus(run)),
              ...signInButtons(
                run,
                item.options,
                busy: chat.busy,
                onSignedIn: () => daemon.reopen(chat),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Codex isn't signed in".
String signInTitle(String agent) => "${agentTitle(agent)} isn't signed in";

/// What a sign-in's button says for [method]: "Sign in with ChatGPT", in
/// the agent's own name for it.
String signInLabel(Option method) {
  final name = method.name.trim();
  if (name.isEmpty) return 'Sign in';
  return name.toLowerCase().startsWith('sign in') ? name : 'Sign in with $name';
}

/// A sign-in's words: what it's for and how it goes ([starts]: a new chat,
/// else a chat that reopens), the agent's own command for a terminal when
/// known, and, unless not [status], a line of where it is ([SignInStatus]),
/// in a line's room whatever it says, so nothing under it moves as it
/// starts.
class SignInLines extends StatelessWidget {
  const new(this.run, {required this.starts, this.status = true, super.key});

  final SignInRun run;
  final bool starts;

  /// Whether the line of where it is shows here.
  final bool status;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final body = theme.ui(t.textSecondary, size: 12.5);
    final command = knownAgents[run.agent]?.signIn ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Text(
          'Sign in to ${starts ? 'start' : 'reopen'} this chat. '
          'Your browser will open for you to sign in, and Nushi never sees '
          'your password.',
          style: body,
        ),
        if (command.isNotEmpty)
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Or run '),
                TextSpan(text: command, style: theme.code(t.text, size: 12)),
                const TextSpan(text: ' in a terminal.'),
              ],
            ),
            style: body,
          ),
        // In a dialog, under the words, in a line's room whatever it
        // says; a card has it in its buttons' row.
        if (status)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 18),
            child: SignInStatus(run),
          ),
      ],
    );
  }
}

/// Where a sign-in is, in a line: waiting on the browser (a spinner and
/// its words), or why the last one failed; nothing before one began.
class SignInStatus extends StatelessWidget {
  const new(this.run, {super.key});

  final SignInRun run;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final failed = run.failed;
    return switch ((run.waiting, failed)) {
      (_?, _) => Row(
        spacing: 8,
        children: [
          SizedBox.square(
            dimension: 14,
            child: FittedBox(child: Spinner(color: t.accentInk)),
          ),
          Expanded(
            child: Text(
              'Waiting for you to finish in the browser…',
              style: theme.ui(t.text, size: 12.5, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
      (null, final why?) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: 14, color: t.crashed),
          ),
          Expanded(child: Text(why, style: theme.ui(t.crashed, size: 12.5))),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// A sign-in's buttons, at the end of its row: a solid button for each of
/// [methods] (the agent's own, as it named them), each staying where it is
/// and off while one runs, and Cancel before them: [onCancel] (a dialog's,
/// which closes it, a sign-in running cancelled with it), else, only while
/// one runs, the sign-in's own. [onSignedIn] once the agent says it's
/// signed in. [busy]: the chat is busy, nothing to do.
List<Widget> signInButtons(
  SignInRun run,
  List<Option> methods, {
  required VoidCallback onSignedIn,
  VoidCallback? onCancel,
  bool busy = false,
}) {
  final waiting = run.waiting != null;
  Future<void> go(Option m) async {
    if (await run.start(m.id)) onSignedIn();
  }

  return [
    if (onCancel != null)
      Button(label: 'Cancel', onPressed: onCancel)
    else if (waiting)
      Button(label: 'Cancel', onPressed: run.cancel),
    for (final m in methods)
      Button(
        label: signInLabel(m),
        kind: ButtonKind.primary,
        autofocus: m == methods.first,
        tooltip: m.description,
        onPressed: waiting || busy ? null : () => unawaited(go(m)),
      ),
  ];
}

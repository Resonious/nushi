import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nushi/attached_files.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/chat_column.dart';
import 'package:nushi/chat_menu.dart';
import 'package:nushi/checks_watch.dart';
import 'package:nushi/composer.dart';
import 'package:nushi/composer_parts.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/github_link_chip.dart';
import 'package:nushi/github_view.dart' show showItem;
import 'package:nushi/new_chat.dart';
import 'package:nushi/pull_link.dart';
import 'package:nushi/review_cards.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/side_chat.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/transcript.dart';
import 'package:nushi/transcript_find.dart';
import 'package:nushi/turn_status.dart';
import 'package:nushi/widgets.dart';

/// A chat's transcript with the composer under it, and its find bar.
/// Escape stops a running turn. What's being written belongs to the chat
/// (its draft), so it outlives the view. The panes beside it, its details
/// and its terminal are the chat area's (`ChatArea`, ADR 0123).
class ChatView extends StatefulWidget {
  const new({required this.chat, required this.daemon, super.key, this.onPull});

  final ChatState chat;
  final Daemon daemon;

  /// Opens the chat's Pull request tab.
  final VoidCallback? onPull;

  /// The narrowest the transcript gets beside a pane alone (the side chat,
  /// the Files pane): narrower, they lie over it.
  static const minWidth = 556.0;

  /// The narrowest the transcript gets beside the details panel: the
  /// window that held the old 264-point panel beside [minWidth] still
  /// holds the 320-point one (ADR 0092), with the window's margins now
  /// around the pane (ADR 0111). Narrower, the panel hides.
  static const leastBesideDetails = 484.0;

  /// The narrowest the transcript gets beside a pane dragged as wide as
  /// it's wanted (a subagent's, or the preview), with the details or not.
  static const leastBesideWide = 360.0;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  bool _dragging = false; // files are dragged over the chat

  Future<void> _ask(String selection) =>
      askAside(context, widget.daemon, widget.chat, selection);

  /// Attaches the files dropped on the chat ([attachFiles]): images as
  /// images when the agent takes them, the rest as file cards.
  Future<void> _drop(DropDoneDetails d) async {
    setState(() => _dragging = false);
    final locked = widget.chat.rewinding.value; // nothing joins the box
    if (d.files.isEmpty || widget.chat.archived || locked) return;
    await attached(
      context,
      attachFiles(widget.chat, d.files, api: widget.daemon.daemonApi),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final transcript = DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _drop,
      child: Container(
        foregroundDecoration: _dragging
            ? BoxDecoration(
                border: Border.all(
                  color: NushiTheme.of(context).t.focus,
                  width: 2,
                ),
              )
            : null,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                stopTurn(context, chat, widget.daemon),
          },
          child: ListenableBuilder(
            listenable: Listenable.merge([chat, chat.forking, chatFullWidth]),
            builder: (context, _) => Stack(
              children: [
                Positioned.fill(
                  child: GitHubLinks(
                    daemon: widget.daemon,
                    chat: chat,
                    onPull: widget.onPull,
                    onShow: (a) => showItem(widget.daemon, a.ref, pull: a.pull),
                    onLink: (a, it) => ChatPull.of(widget.daemon, chat).addLink(
                      GitHubLink(
                        host: a.host,
                        id: it.id,
                        repo: a.repo,
                        number: a.number,
                        pull: true,
                      ),
                    ),
                    child: Transcript(
                      chat: chat,
                      daemon: widget.daemon,
                      onReply: chat.archived || chat.sessionGone
                          ? null
                          : chat.draft.addReply,
                      onSide: chat.archived || chat.sessionGone ? null : _ask,
                      // Under it, its scrollbar running down beside them.
                      bottom: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TurnStatus(
                            chat,
                            what: chat.forking.value
                                ? 'Starting a side chat'
                                : null,
                          ),
                          if (chat.mcpChanged && !chat.archived)
                            _McpChanged(chat, widget.daemon),
                          if (chat.checksFailed.isNotEmpty && !chat.archived)
                            ChecksFailedBar(chat, widget.daemon),
                          if (!chat.archived && !chat.sessionGone)
                            UnsentReview(chat),
                          if (chat.archived)
                            _Archived(chat, widget.daemon)
                          else if (chat.sessionGone)
                            _Expired(chat, widget.daemon)
                          else
                            Composer(
                              chat: chat,
                              daemon: widget.daemon,
                              folder: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // ⌘F: the find bar, over the transcript's top right.
                ListenableBuilder(
                  listenable: chat.find,
                  builder: (context, _) => chat.find.query == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              NushiTheme.gutter,
                              8,
                              NushiTheme.gutter,
                              0,
                            ),
                            child: FindBar(
                              chat.find,
                              loadAll: chat.older > 0
                                  ? () => unawaited(
                                      widget.daemon.loadOlder(chat, all: true),
                                    )
                                  : null,
                              loading: chat.loadingOlder,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return transcript;
  }
}

/// In place of the composer for an archived chat: it is read-only until
/// unarchived.
class _Archived extends StatelessWidget {
  const new(this.chat, this.daemon);

  final ChatState chat;
  final Daemon daemon;

  @override
  Widget build(BuildContext context) => _ReadOnlyBar(
    words: chat.items.isEmpty
        ? 'Archived. Unarchive it to see its history and go on.'
        : 'Archived. Unarchive it to go on.',
    actions: [
      RunButton(
        label: 'Unarchive',
        kind: ButtonKind.primary,
        run: () =>
            daemon.client.archiveChat(ArchiveChatRequest(chatId: chat.id)),
      ),
    ],
  );
}

/// In place of the composer for a chat that can't go on: a line over it,
/// [icon] and [words] saying why, and [actions] at its end.
class _ReadOnlyBar extends StatelessWidget {
  const new({required this.words, required this.actions, this.icon});

  final String words;
  final List<Widget> actions;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.line)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NushiTheme.gutter,
        vertical: 10,
      ),
      child: Row(
        spacing: NushiTheme.barGap,
        children: [
          if (icon case final icon?) Icon(icon, size: 15, color: t.textMuted),
          Expanded(child: Text(words, style: theme.ui(t.textSecondary))),
          ...actions,
        ],
      ),
    );
  }
}

/// Over the composer once MCP servers changed for the chat's folder: the
/// agent keeps the ones it started with until the chat reloads.
class _McpChanged extends StatelessWidget {
  const new(this.chat, this.daemon);

  final ChatState chat;
  final Daemon daemon;

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    return ChatColumn(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NushiTheme.gutter,
          vertical: 4,
        ),
        child: Row(
          children: [
            Icon(Icons.hub_outlined, size: 13, color: t.textMuted),
            const SizedBox(width: 6),
            Text(
              'MCP servers changed. Reload to use them.',
              style: theme.ui(t.textSecondary, size: 12),
            ),
            const SizedBox(width: NushiTheme.barGap),
            ReloadButton(chat, daemon),
          ],
        ),
      ),
    );
  }
}

/// Reloads a chat's agent (asking first when that stops background
/// work), so it picks up changed MCP servers; disabled while it works.
class ReloadButton extends StatelessWidget {
  const new(this.chat, this.daemon, {super.key});

  final ChatState chat;
  final Daemon daemon;

  @override
  Widget build(BuildContext context) => tooltip(
    context,
    chat.busy ? 'Once ${chat.agentName} is done' : '',
    RunButton(
      label: 'Reload',
      run: chat.busy ? null : () => reloadChat(context, chat, daemon),
    ),
  );
}

/// In place of the composer for a chat whose session its agent deleted
/// (its notice says so): it is read-only, its transcript Nushi's copy, if
/// it has one (ADR 0047). A new chat can start where it was.
class _Expired extends StatelessWidget {
  const new(this.chat, this.daemon);

  final ChatState chat;
  final Daemon daemon;

  @override
  Widget build(BuildContext context) => _ReadOnlyBar(
    icon: Icons.history_toggle_off,
    words: chat.items.any((it) => it.kind != ItemKind.ITEM_KIND_NOTICE)
        ? 'Read-only: Nushi’s copy of the transcript.'
        : 'Read-only.',
    actions: [
      Button(
        label: 'Delete…',
        kind: ButtonKind.destructive,
        onPressed: () => showDeleteChat(context, chat, daemon),
      ),
      Button(
        label: 'Start a new chat here',
        kind: ButtonKind.primary,
        onPressed: () =>
            newChat(context, daemon, chat.scratch ? '' : chat.folder),
      ),
    ],
  );
}

import 'dart:async';
import 'dart:math';

import 'package:connectrpc/connect.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';

/// A chat's items as the daemon pages them (internal/api's GetChat with
/// `recent`, GetChatItems): a page reaches back to the call of a subagent
/// whose steps are in it, and the recent part comes with the tasks running
/// before it; FindInChat counts a query's matches in each item's text and
/// title, case aside. Every request is in [asked]; while [fail] is set a
/// page fails, while [hold] is set a page waits for it, and while
/// [holdFind] is set a find does.
class PagedChat {
  new(this.chat, this.items);

  final Chat chat;
  final List<Item> items;
  final asked = <Object>[];
  bool fail = false;
  Completer<void>? hold;
  Completer<void>? holdFind;

  /// FakeDaemon's answer for this chat's GetChat and GetChatItems.
  Object? answer(Object input) => switch (input) {
    GetChatRequest(:final chatId) when chatId == chat.id => _chat(input),
    GetChatItemsRequest(:final chatId) when chatId == chat.id => _page(input),
    FindInChatRequest(:final chatId) when chatId == chat.id => _find(input),
    _ => null,
  };

  Future<FindInChatResponse> _find(FindInChatRequest r) async {
    asked.add(r);
    if (holdFind case final h?) await h.future;
    final end = r.before.isEmpty
        ? items.length
        : items.indexWhere((it) => it.id == r.before);
    if (end < 0) throw ConnectException(Code.notFound, 'no such item');
    final q = r.text.toLowerCase();
    return FindInChatResponse(
      matches: [
        for (final it in items.take(end))
          if (q.allMatches('${it.title}\n${it.text}'.toLowerCase()).length
              case final n when n > 0)
            ChatMatch(itemId: it.id, count: n),
      ],
    );
  }

  GetChatResponse _chat(GetChatRequest r) {
    asked.add(r);
    final start = r.recent > 0 ? _start(items.length, r.recent) : 0;
    return GetChatResponse(
      chat: chat,
      status: chat.status,
      items: items.sublist(start),
      older: start,
      running: [
        for (final it in items.take(start))
          if (it.backgroundCommand.state == 'running' ||
              it.subagent.state == 'running')
            it,
      ],
    );
  }

  Future<GetChatItemsResponse> _page(GetChatItemsRequest r) async {
    asked.add(r);
    if (hold case final h?) await h.future;
    if (fail) throw ConnectException(Code.unavailable, 'the link dropped');
    final end = items.indexWhere((it) => it.id == r.before);
    if (end < 0) throw ConnectException(Code.notFound, 'no such item');
    final n = r.limit <= 0 || r.limit > 500 ? 500 : r.limit;
    var start = _start(end, n);
    if (r.through.isNotEmpty) {
      final at = items.indexWhere((it) => it.id == r.through);
      if (at < 0) throw ConnectException(Code.notFound, 'no such item');
      if (at < start) {
        start = _start(end, end - max(0, max(at - n, end - 2000)));
      }
    }
    return GetChatItemsResponse(items: items.sublist(start, end), older: start);
  }

  /// The daemon's pageStart.
  int _start(int end, int n) {
    var start = end - n < 0 ? 0 : end - n;
    final index = {for (final (i, it) in items.take(end).indexed) it.id: i};
    for (var i = end - 1; i >= start; i--) {
      if (index[items[i].parent] case final j? when j < start) start = j;
    }
    return start;
  }

  /// The pages asked for after the first load.
  Iterable<GetChatItemsRequest> get pages =>
      asked.whereType<GetChatItemsRequest>();
}

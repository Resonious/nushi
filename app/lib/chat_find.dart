import 'dart:async';
import 'dart:math';

import 'package:connectrpc/connect.dart';
import 'package:flutter/foundation.dart';

import 'package:nushi/chat.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/transcript_find.dart';

/// The daemon's API that finds in a chat's whole history (FindInChat).
const findInChatApi = 136;

/// Asks the daemon for a find's matches in a chat's items before one; null
/// when it can't (older than [findInChatApi]).
typedef AskAbove = Future<FindInChatResponse?> Function(
  FindInChatRequest request,
  CancelableSignal signal,
);

/// ⌘F in a chat's transcript, the whole chat (ADR 0144). The daemon counts
/// the matches in the items above what's loaded ([ask], FindInChat); each
/// is a hit keyed `far <item> <n>`, before the matches the transcript
/// finds in what's loaded. A step to one asks the transcript to load up to
/// its item ([pending]); once it's in and laid out, the step lands on that
/// item's own matches there. Typing goes to the first match loaded (the
/// nearest above with none), loading nothing.
class ChatFind extends Find {
  new(this._chat);

  final ChatState _chat;

  /// Set by the chat's transcript: the daemon's search, and the key of
  /// an item's entry (Marks.entry) once it's laid out, else null.
  AskAbove? ask;
  String? Function(String item)? entryOf;

  /// How long typing pauses before the daemon is asked.
  static const Duration pause = Waits.typing;

  List<ChatMatch> _far = const [];
  List<String> _near = const [];
  Timer? _wait;
  CancelableSignal? _asking;
  bool _typed = false; // no step since the query changed
  int _stepAsk = -1;

  /// The daemon is being asked.
  bool get searching => _wait != null || _asking != null;

  /// The daemon searched what isn't loaded: no Load all.
  bool get whole => _whole;
  bool _whole = false;

  /// The daemon's search stopped at its bound: the count is a floor.
  bool get more => _more;
  bool _more = false;

  /// The far hit a step went to, until its item's matches are laid out.
  String? get pending => _pending;
  String? _pending;

  /// Whether the last ask to show the current hit was a step.
  bool get stepped => asked == _stepAsk;

  /// The item of a far hit's [key]; null for a hit in what's loaded.
  static String? farItem(String? key) =>
      key != null && key.startsWith('far ') ? key.split(' ')[1] : null;

  @override
  String get count {
    final q = query ?? '';
    if (q.isNotEmpty && hits.isEmpty && searching) return '';
    final c = super.count;
    return _more && hits.isNotEmpty ? '$c+' : c;
  }

  @override
  set query(String? q) {
    if (q == query) return;
    _typed = true;
    _pending = null;
    super.query = q;
    _askAbove();
  }

  @override
  void close() {
    _cancel();
    _far = const [];
    _near = const [];
    _whole = _more = false;
    _pending = null;
    super.close();
  }

  /// The chat took a fresh snapshot (a reconnect, a rewind): what was
  /// counted above may be gone, so it's asked again.
  void reloaded() {
    if ((query ?? '').isNotEmpty) _askAbove();
  }

  void _cancel() {
    _wait?.cancel();
    _wait = null;
    _asking?.cancel();
    _asking = null;
  }

  /// Asks the daemon about what's above the loaded part, after a pause,
  /// cancelling what it asked before. With nothing above, the loaded find
  /// is all of it.
  void _askAbove() {
    _cancel();
    _far = const [];
    _whole = _more = false;
    final q = query ?? '';
    if (q.isEmpty || ask == null || _chat.older == 0 || _chat.items.isEmpty) {
      _merge();
      return;
    }
    _wait = Timer(pause, () {
      _wait = null;
      unawaited(_askNow(q));
    });
    _merge();
  }

  Future<void> _askNow(String q) async {
    final signal = _asking = CancelableSignal();
    FindInChatResponse? r;
    try {
      r = await ask!(
        FindInChatRequest(
          chatId: _chat.id,
          text: q,
          before: _chat.items.first.id,
        ),
        signal,
      );
    } on Object {
      r = null; // the loaded find, with Load all, as before
    }
    if (signal != _asking) return;
    _asking = null;
    if (r != null) {
      _far = r.matches;
      _more = r.more;
      _whole = true;
    }
    _merge();
  }

  @override
  void found(List<String> hits) {
    _near = hits;
    _merge();
  }

  @override
  void step(int by) {
    if (hits.isEmpty) return;
    _typed = false;
    // Set before the step tells its listeners: the transcript loads a far
    // one's part as it hears of it.
    _stepAsk = asked + 1;
    final next = hits[(at + by) % hits.length];
    _pending = farItem(next) == null ? null : next;
    super.step(by);
  }

  /// The hits: the far ones whose items aren't laid out (not loaded, or
  /// loaded and not yet built), then the loaded ones. A pending step lands
  /// once its item is laid out.
  void _merge() {
    final far = <String>[
      for (final m in _far)
        if (entryOf?.call(m.itemId) == null)
          for (var k = 0; k < m.count; k++) 'far ${m.itemId} $k',
    ];
    final all = [...far, ..._near];
    if (_pending case final p? when !far.contains(p)) {
      _pending = null;
      final i = _landing(p, all);
      foundAt(all, i ?? min(far.length, max(0, all.length - 1)), ask: true);
      return;
    }
    if (all.isEmpty) {
      if (hits.isNotEmpty || at != 0) foundAt(const [], 0);
      return;
    }
    final was = current;
    final int i;
    if (_typed) {
      i = _near.isNotEmpty ? far.length : all.length - 1;
    } else if (was != null && all.contains(was)) {
      i = all.indexOf(was);
    } else {
      i = min(at, all.length - 1);
    }
    if (listEquals(all, hits) && i == at) return;
    foundAt(all, i);
  }

  /// Where far hit [key] lands among [all]: its item's entry's match of
  /// the same place, or its last.
  int? _landing(String key, List<String> all) {
    final parts = key.split(' ');
    final entry = entryOf?.call(parts[1]);
    if (entry == null) return null;
    final mine = [
      for (final (i, k) in all.indexed)
        if (k.startsWith('$entry ')) i,
    ];
    if (mine.isEmpty) return null;
    return mine[min(int.parse(parts[2]), mine.length - 1)];
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}

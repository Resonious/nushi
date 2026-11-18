import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:nushi/changes_span.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/errors.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/line_changes.dart';
import 'package:nushi/motion.dart';
import 'package:nushi/preview.dart' show FileWatch;

// What a shown file's change marks count from, asked of the daemon, and
// why there are none when there are none (ADR 0131): its path row says
// one or the other, so a file never opens to an unexplained blank gutter.

/// What a file's change marks count from (ADR 0131).
enum MarksFrom {
  /// Where the chat's branch left its base ([LineBase.against]), the
  /// Branch view's comparison.
  branch,

  /// Before the chat's own commits, on the branch it counts from itself
  /// (the default branch): the parent of the oldest of the branch's
  /// latest commits made since the chat began.
  chat,

  /// The last commit: no branch base, and no commit since the chat began
  /// (or a file outside the chat's folder).
  lastCommit,
}

/// Why a file shows no change marks, in the words its path row says.
enum NoMarks {
  notRepository('Not in a git repository'),
  ignored('Ignored by git'),
  link('A link: no change marks'),
  binary('Not text: no change marks'),
  tooLarge('Too large for change marks'),
  tooManyLines('Over 10,000 lines: no change marks'),
  otherRepository('A repository of its own'),
  oldDaemon('Change marks need a newer daemon'),
  failed('Couldn’t compare with git');

  new(this.label);
  final String label;
}

/// A base found: what GetDiff's `base` is ('' for the last commit), and
/// what that is.
typedef _Base = ({String base, MarksFrom from});

const _Base _lastCommit = (base: '', from: MarksFrom.lastCommit);

/// A shown file's text before its chat's work, what its change marks are
/// drawn against ([value]; null draws none), and what its path row says
/// of them (ADR 0131). The base is, by [from]: where the chat's branch
/// left its base ([MarksFrom.branch]), the one the Changes tab's Branch
/// view counts from (`ChangeSpan.branchBase`); on that branch itself (a
/// chat on the default branch), from before the chat's own commits
/// ([MarksFrom.chat]); else the last commit. A file outside the chat's
/// folder (another root, so another repository) counts from its last
/// commit. A file new against the base ([isNew]: untracked, or added
/// since) has the empty text as its base, so every line is marked added.
/// Asked of the daemon (GetDiff with the file's path and the base, API
/// [oneFileDiffApi]) as the file changes on disk, the chat's turn ends, it
/// commits or its folder or worktree changes; the base itself is found
/// again when the turn ends, it commits or the folder changes. The file's
/// own folder is asked, so a file in a nested repository is compared
/// against its own repository. Where there are no marks, [none] says why;
/// [changed] counts the lines that differ in the file as saved.
class LineBase extends ChangeNotifier implements ValueListenable<String?> {
  new(this.daemon, this.chat, this.watch) {
    _folder = chat.folder;
    _worktree = chat.worktree?.base ?? '';
    _commits = chat.commits;
    _wasBusy = chat.busy;
    chat.addListener(_chatChanged);
    watch.addListener(_fileChanged);
    _fileChanged();
  }

  final Daemon daemon;
  final ChatState chat;
  final FileWatch watch;

  String? _base;
  bool _isNew = false;
  MarksFrom _from = MarksFrom.lastCommit;
  String _against = '';
  NoMarks? _none;
  String _error = '';
  int _changed = 0;
  bool _loaded = false;
  bool _slow = false;
  Timer? _slowly;

  @override
  String? get value => _base;

  /// Whether the file is new against the base (untracked, added to the
  /// index, or added on the branch): its every line is marked added.
  bool get isNew => _isNew;

  /// What [value] is.
  MarksFrom get from => _from;

  /// The branch [from] names, with [MarksFrom.branch]: as the Branch view
  /// has it ("origin/main"; a commit's hash when the base branch is gone).
  String get against => _against;

  /// Why there are no marks, when there are none to draw and the file
  /// isn't simply unchanged.
  NoMarks? get none => _none;

  /// The daemon's words, when asking it failed ([NoMarks.failed]).
  String get error => _error;

  /// The lines added, changed and removed in the file as saved; 0 when
  /// it's the same as the base (or there's none).
  int get changed => _changed;

  /// Whether an answer has come for the file yet.
  bool get loaded => _loaded;

  /// Whether the first answer is taking more than a moment ([Waits.slow]).
  bool get slow => _slow && !_loaded;

  /// What the marks count from, as the path row and a mark's card say it:
  /// "since main", "since this chat began", "since the last commit".
  String get since => switch (_from) {
    MarksFrom.branch => 'since ${baseName(_against)}',
    MarksFrom.chat => 'since this chat began',
    MarksFrom.lastCommit => 'since the last commit',
  };

  String? _sha;
  late String _folder;
  late String _worktree;
  late int _commits;
  late bool _wasBusy;
  Future<_Base>? _branchBase; // the base found, until it may have changed
  int _asked = 0; // only the latest question's answer lands
  bool _disposed = false;

  void _fileChanged() {
    final f = watch.file;
    // A file too large comes without its text: asked once, to say so.
    final sha = f == null || f.missing
        ? null
        : f.tooLarge
        ? 'too large'
        : f.sha256;
    if (sha == _sha) return;
    _sha = sha;
    unawaited(ask());
  }

  void _chatChanged() {
    final ended = _wasBusy && !chat.busy;
    _wasBusy = chat.busy;
    final worktree = chat.worktree?.base ?? '';
    final moved = _folder != chat.folder || _worktree != worktree;
    final committed = _commits != chat.commits;
    if (ended || moved || committed) {
      // A commit can be the chat's first, which moves its start.
      _branchBase = null;
      _folder = chat.folder;
      _worktree = worktree;
      _commits = chat.commits;
      unawaited(ask());
    }
  }

  /// What the file's marks count from in the chat's folder: the branch
  /// the Branch view counts from, or on that branch itself from before
  /// the chat's commits ([_chatStart]). A failure is found again next
  /// time.
  Future<_Base> _findBase() async {
    try {
      final b = await ChangeSpan.branchBase(daemon, chat);
      if (!b.status.git) return _lastCommit;
      final span = ChangeSpan(chat.folder, Scope.branch, b.base, b.status);
      if (!span.onBase) return (base: b.base, from: MarksFrom.branch);
      return await _chatStart();
    } on Object {
      _branchBase = null;
      return _lastCommit;
    }
  }

  /// On the branch it counts from (the default branch): from the parent
  /// of the oldest of the branch's latest commits (ListCommits' last 50)
  /// made since the chat began, so the chat's own commits stay marked;
  /// with none, the last commit. A commit of the user's made meanwhile on
  /// that branch counts too: the daemon doesn't know whose a commit is.
  Future<_Base> _chatStart() async {
    final r = await daemon.client.listCommits(
      ListCommitsRequest(folder: chat.folder),
    );
    final began = chat.created.millisecondsSinceEpoch ~/ 1000;
    final own = r.commits.takeWhile((c) => c.unixSeconds.toInt() >= began);
    if (own.isEmpty) return _lastCommit;
    return (base: '${own.last.hash}^', from: MarksFrom.chat);
  }

  /// Asks again what the file was before the chat's work.
  Future<void> ask() async {
    final asked = ++_asked;
    final f = watch.file;
    if (f == null || f.missing) return;
    if (!_loaded) {
      _slowly ??= Timer(Waits.slow, () {
        _slow = true;
        if (!_disposed) notifyListeners();
      });
    }
    if (f.tooLarge) return await _land(asked, none: NoMarks.tooLarge);
    if (watch.notText) return await _land(asked, none: NoMarks.binary);
    if (daemon.daemonApi < oneFileDiffApi) {
      return await _land(asked, none: NoMarks.oldDaemon);
    }
    final now = utf8.decode(f.data, allowMalformed: true);
    final abs = f.path.isNotEmpty
        ? f.path
        : absoluteIn(chat.folder, watch.path);
    final slash = abs.lastIndexOf('/');
    if (slash < 0) return await _land(asked, none: NoMarks.failed);
    final inChat = abs.startsWith('${chat.folder}/');
    final found = inChat ? await (_branchBase ??= _findBase()) : _lastCommit;
    if (_disposed || asked != _asked) return;
    Future<GetDiffResponse> diff(String base) => daemon.client.getDiff(
      GetDiffRequest(
        folder: slash == 0 ? '/' : abs.substring(0, slash),
        path: abs.substring(slash + 1),
        base: base,
      ),
    );
    var against = found;
    GetDiffResponse r;
    try {
      try {
        r = await diff(against.base);
      } on Object {
        // Not a branch or commit of the file's own repository (a nested
        // one), or the chat's first commit was the repository's first:
        // from its last commit instead.
        if (against.base.isEmpty) rethrow;
        against = _lastCommit;
        r = await diff('');
      }
    } on Object catch (e) {
      final words = errorText(e);
      final notGit = RegExp(
        'not (in )?a git repository',
        caseSensitive: false,
      ).hasMatch(words);
      return await _land(
        asked,
        none: notGit ? NoMarks.notRepository : NoMarks.failed,
        error: notGit ? '' : words,
      );
    }
    if (r.files.isEmpty) {
      // Tracked and unchanged: its text then is this.
      return await _land(asked, base: now, now: now, at: against);
    }
    final c = r.files.first;
    if (c.skipped.isNotEmpty) {
      return await _land(
        asked,
        none: _skipped(c),
        error: c.skipped,
        at: against,
      );
    }
    return await switch (c.status) {
      'modified' ||
      'renamed' => _land(asked, base: c.oldText, now: now, at: against),
      'untracked' ||
      'added' => _land(asked, base: '', now: now, isNew: true, at: against),
      final s => _land(
        asked,
        none: NoMarks.failed,
        error: 'git lists it as $s',
        at: against,
      ),
    };
  }

  /// Why the daemon left a file's text out.
  static NoMarks _skipped(FileChange c) => switch (c.skipped) {
    'not tracked' => NoMarks.ignored,
    'a link' => NoMarks.link,
    'binary' => NoMarks.binary,
    'too large' => NoMarks.tooLarge,
    'a submodule' || 'a repository of its own' => NoMarks.otherRepository,
    _ => NoMarks.failed,
  };

  /// Lands an answer for question [asked], the latest: [base] against
  /// [now] (the file as saved), or [none] and why.
  Future<void> _land(
    int asked, {
    String? base,
    String now = '',
    bool isNew = false,
    NoMarks? none,
    String error = '',
    _Base at = _lastCommit,
  }) async {
    var changed = 0;
    var text = base;
    var why = none;
    if (text != null && tooLongToMark(text, now)) {
      // Past the diff's limit: no marks, but a new file stays new.
      text = null;
      if (!isNew) why = NoMarks.tooManyLines;
    } else if (text != null) {
      final marks = await lineMarksSoon(text, now);
      for (final m in marks) {
        changed += m.kind == MarkKind.removed ? m.old.length : m.count;
      }
    }
    if (_disposed || asked != _asked) return;
    _slowly?.cancel();
    final same =
        _loaded &&
        text == _base &&
        isNew == _isNew &&
        at.from == _from &&
        at.base == _against &&
        why == _none &&
        error == _error &&
        changed == _changed;
    _loaded = true;
    if (same) return;
    _base = text;
    _isNew = isNew;
    _from = at.from;
    _against = at.base;
    _none = why;
    _error = error;
    _changed = changed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _slowly?.cancel();
    chat.removeListener(_chatChanged);
    watch.removeListener(_fileChanged);
    super.dispose();
  }
}

/// A base branch's name as the path row says it: a remote's `origin/`
/// left off ("main"), a commit's hash shortened.
String baseName(String base) {
  if (RegExp(r'^[0-9a-f]{40}$').hasMatch(base)) return base.substring(0, 7);
  return base.startsWith('origin/') ? base.substring(7) : base;
}

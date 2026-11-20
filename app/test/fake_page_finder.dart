import 'package:flutter/foundation.dart';
import 'package:nushi/transcript_find.dart';
import 'package:nushi/web_find.dart';

/// A web view's find as a test has it: it finds in [text] (case aside),
/// says whether the web view has the keys ([hasKeys]), and records what
/// it's asked, in order.
class FakePageFinder implements PageFinder {
  new(this.text);

  /// The page's text.
  String text;

  /// Whether the web view has the keys.
  bool hasKeys = false;

  /// What it was asked: `find <query> <at>`, `show <at>`, `clear`, `focus`.
  final asked = <String>[];

  /// The colours the last find was given.
  FindColors? colors;

  int _count = 0;
  final _loaded = ValueNotifier<int>(0);

  /// A page finished loading.
  void load() => _loaded.value++;

  @override
  Listenable get loaded => _loaded;

  @override
  Future<PageFound> find(
    String query, {
    required int at,
    required FindColors colors,
    required double cover,
  }) async {
    asked.add('find $query $at');
    this.colors = colors;
    final q = query.toLowerCase();
    _count = q.isEmpty ? 0 : q.allMatches(text.toLowerCase()).length;
    return (count: _count, at: at);
  }

  @override
  Future<PageFound> show(int at, {required double cover}) async {
    asked.add('show $at');
    return (count: _count, at: at);
  }

  @override
  Future<void> clear() async => asked.add('clear');

  @override
  Future<bool> focused() async => hasKeys;

  @override
  Future<void> focus() async => asked.add('focus');
}

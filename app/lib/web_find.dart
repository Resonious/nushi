import 'package:flutter/widgets.dart';

import 'package:nushi/preview_find.dart';
import 'package:nushi/run_state.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/transcript_find.dart';

// ⌘F in a web view (issue 63, ADR 0143): a file's HTML page and a browser
// tab find with the page's own text, through its host's [PageFinder] (the
// Mac's runs a script in a world of its own, `web_find_macos.dart`), in the
// transcript's bar laid over the page. A host with no finder (Linux's
// placeholder, Windows's WebView2 for now) has no find.

/// What a page's find found: how many matches, and which is current.
typedef PageFound = ({int count, int at});

/// A web view's find of its page's text, case aside.
abstract interface class PageFinder {
  /// Marks every match of [query] in [colors], the [at]th current and in
  /// view below [cover] points of the page's top (the bar's); '' marks
  /// none.
  Future<PageFound> find(
    String query, {
    required int at,
    required FindColors colors,
    required double cover,
  });

  /// Makes the [at]th match of the last [find] current, and brings it into
  /// view.
  Future<PageFound> show(int at, {required double cover});

  /// Takes the marks away.
  Future<void> clear();

  /// Whether the web view has the keys (Flutter doesn't see them then).
  Future<bool> focused();

  /// Gives the web view the keys back.
  Future<void> focus();

  /// Tells of each page that finishes loading, whose marks are gone.
  Listenable get loaded;
}

/// The finds of the pages on screen, which ⌘F asks whether their web view
/// has the keys ([focusedPageFind]): one is in it while its page shows.
final Set<WebFind> pageFinds = runSet();

/// The find of the page whose web view has the keys, if any: ⌘F then comes
/// from the menu bar, WebKit having taken the key.
Future<WebFind?> focusedPageFind() async {
  for (final f in [...pageFinds]) {
    try {
      if (await f.finder.focused()) return f;
    } on Object {
      // No answer: not this one.
    }
  }
  return null;
}

/// [Find] over a page, through its [finder]: the page answers each query
/// with a count, its matches are numbered, and a step asks it to show the
/// next. Answers come in the order asked; one overtaken by a later query
/// is dropped. Esc gives the keys back to where they were as the bar
/// opened: the web view when ⌘F came from it ([openFromPage]), else the
/// Flutter field that had them (a browser tab's address field), as
/// [PreviewFind] does.
class WebFind extends Find {
  new(this.finder) {
    finder.loaded.addListener(_reloaded);
  }

  final PageFinder finder;

  /// The theme's find colours, set by the view as it builds.
  FindColors colors = findColors(Tokens.light);

  int _asks = 0;
  int _answered = 0;
  Future<void> _last = Future.value();

  /// Whether the page is still to answer the latest query: the count
  /// stays the last one's, never "None" for a query not looked for yet.
  bool get looking => _answered != _asks;

  @override
  String get count => looking && hits.isEmpty ? '' : super.count;

  /// Runs [ask] after those before it.
  void _then(Future<void> Function() ask) {
    _last = _last.then((_) => ask()).catchError((Object _) {});
  }

  @override
  set query(String? q) {
    super.query = q;
    _look();
  }

  void _look() {
    final q = query ?? '';
    final ask = ++_asks;
    _then(() async {
      PageFound found;
      try {
        found = await finder.find(
          q,
          at: 0,
          colors: colors,
          cover: findBarCover,
        );
      } on Object {
        found = (count: 0, at: 0); // no answer (no page yet): none
      }
      if (ask != _asks || query == null) return;
      _answered = ask;
      foundAt([for (var i = 0; i < found.count; i++) '$i'], found.at);
    });
  }

  @override
  void step(int by) {
    if (!canStep) return;
    super.step(by);
    final to = at;
    _then(() => finder.show(to, cover: findBarCover));
  }

  /// A new page, or the same again: its marks are gone, so it's looked in
  /// anew while the bar is open.
  void _reloaded() {
    if (query != null) _look();
  }

  // Where the keys were as the bar opened: the web view, or a Flutter node.
  bool _fromPage = false;
  FocusNode? _back;

  /// Opens the bar from the web view, which had the keys: Flutter's focus
  /// is wherever it was before the page took them, so it isn't kept.
  void openFromPage() {
    if (query == null) {
      _fromPage = true;
      _back = null;
    }
    super.open();
  }

  @override
  void open() {
    if (query == null) {
      _fromPage = false;
      final now = FocusManager.instance.primaryFocus;
      _back = now == focus ? null : now;
    }
    super.open();
  }

  @override
  void close() {
    final had = focus.hasFocus;
    final (fromPage, back) = (_fromPage, _back);
    _fromPage = false;
    _back = null;
    _answered = ++_asks;
    super.close();
    _then(finder.clear);
    if (!had) return;
    if (fromPage) {
      focus.unfocus();
      _then(finder.focus);
    } else if (back != null && back.context != null && back.canRequestFocus) {
      back.requestFocus();
    } else {
      focus.unfocus();
    }
  }

  @override
  void dispose() {
    finder.loaded.removeListener(_reloaded);
    pageFinds.remove(this);
    super.dispose();
  }
}

/// A page's [find] over [child], its bar at the top right, the find in
/// [pageFinds] while this shows and given the theme's colours.
class PageFindFrame extends StatefulWidget {
  const new({required this.find, required this.child, super.key});

  final WebFind find;
  final Widget child;

  @override
  State<PageFindFrame> createState() => _PageFindFrameState();
}

class _PageFindFrameState extends State<PageFindFrame> {
  @override
  void initState() {
    super.initState();
    pageFinds.add(widget.find);
  }

  @override
  void didUpdateWidget(PageFindFrame old) {
    super.didUpdateWidget(old);
    if (old.find != widget.find) {
      pageFinds
        ..remove(old.find)
        ..add(widget.find);
    }
  }

  @override
  void dispose() {
    pageFinds.remove(widget.find);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FindFrame(
    find: widget.find..colors = findColors(NushiTheme.of(context).t),
    hint: 'Find in the page',
    child: widget.child,
  );
}

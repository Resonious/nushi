import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:nushi/daemon.dart' show dataDir;
import 'package:nushi/outside_page.dart';
import 'package:nushi/theme/tokens.dart';
import 'package:nushi/web_page.dart';
import 'package:nushi/web_view_windows.dart';

// A file's preview on Windows (ADR 0068, 0134): a WebView2 of the runner's
// (`web_view_windows.dart`).

/// A WebView2 serving the page's root folder (the chat's, or the file's
/// own) under a host of its own, so the page reads files inside it and
/// none outside; in-private, so it keeps nothing and carries no browser's
/// sign-ins. Its main frame shows the file alone (a reload, an anchor, a
/// query); a link the user clicks elsewhere opens in the default browser,
/// a file under the root as itself. Without the WebView2 runtime it's the
/// placeholder that opens the page in the browser ([OutsidePage]).
class WindowsPage implements PageHost {
  new() {
    _web.onLeave = _leave;
    unawaited(_web.ready.then((made) => _made.value = made));
  }

  /// Its web view (a test reads the page through it).
  @visibleForTesting
  WebView2 get web => _web;

  final _web = WebView2(
    folder: webViewFolder(dataDir),
    background: Tokens.light.base, // a page's own ground, as a browser's
  );
  final _made = ValueNotifier<bool?>(null);
  final _outside = OutsidePage();
  String _root = '';
  String _path = '';

  @override
  Widget view(BuildContext context) => ValueListenableBuilder(
    valueListenable: _made,
    builder: (context, made, _) => switch (made) {
      false => _outside.view(context),
      _ => _web.view(),
    },
  );

  @override
  Future<void> load(String path, String root) async {
    unawaited(_outside.load(path, root));
    if (!await _web.ready) return;
    final served = servedRoot(path, root);
    final host = pageHost(served);
    if (served != _root) await _web.map(host, served);
    _root = served;
    _path = path;
    await _web.load('${pageUrl(path, served, host)}');
  }

  /// WebView2's reload reads the page's files again and keeps where it
  /// was scrolled to.
  @override
  Future<void> reload() async {
    if (_path.isNotEmpty) await _web.reload();
  }

  void _leave(String url) {
    final to = Uri.tryParse(url);
    if (to == null) return;
    final open = leaving(to, _root);
    if (open != null) unawaited(openInBrowser(open).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _web.close();
    _outside.dispose();
    _made.dispose();
  }
}

/// The folder a page at [path] is served from: [root] when the file is in
/// it, else the file's own (Windows's names case aside).
String servedRoot(String path, String root) {
  final p = path.toLowerCase();
  final r = root.toLowerCase().replaceFirst(RegExp(r'\\+$'), '');
  if (r.isNotEmpty && p.startsWith('$r\\')) return root;
  return path.substring(0, path.lastIndexOf(r'\'));
}

/// The host a page under [root] is served as: one per root, so pages of
/// two folders don't share an origin (their storage, while the web view
/// lasts). `.example` is reserved: no real site has it.
String pageHost(String root) {
  // SHA-256's first 64 bits over the root, case aside: two roots can't
  // be made to share a host (a 32-bit hash's collision is easy to find).
  final hash = sha256.convert(utf8.encode(root.toLowerCase()));
  return 'p${'$hash'.substring(0, 16)}.nushi.example';
}

/// What the default browser opens for [to], an address a page served
/// from [root] left for: a file under the root as itself, another
/// address as it is, but a `file:` address only for a file inside [root]
/// (null for any other). One with a host, or a path that starts `\\`,
/// is a UNC path, which Windows opens over SMB and so sends the user's
/// NTLM credentials to that host; one outside the root is a file the
/// page had no business naming.
Uri? leaving(Uri to, String root) {
  if (to.host == pageHost(root)) return servedFile(to, root);
  if (to.scheme != 'file') return to;
  if (to.host.isNotEmpty) return null;
  final String path;
  try {
    path = to.toFilePath(windows: true);
  } on Object {
    return null;
  }
  final r = root.toLowerCase().replaceFirst(RegExp(r'\\+$'), '');
  if (path.startsWith(r'\\') ||
      r.isEmpty ||
      !path.toLowerCase().startsWith('$r\\') ||
      path.indexOf(':', 2) >= 0 || // a stream, or a second drive
      path.split(RegExp(r'[\\/]')).any((n) => n == '..' || n == '.')) {
    return null;
  }
  return Uri.file(path, windows: true);
}

/// The address of the file at [path], inside [root], as [host] serves it.
Uri pageUrl(String path, String root, String host) {
  final names = path.substring(root.length).split(RegExp(r'[\\/]'))
    ..removeWhere((n) => n.isEmpty);
  return Uri(scheme: 'https', host: host, pathSegments: names);
}

/// The file [url] (an address [pageUrl] made) names inside [root], or
/// null for one that would leave it.
Uri? servedFile(Uri url, String root) {
  final names = url.pathSegments.where((n) => n.isNotEmpty).toList();
  if (names.any((n) => n == '..' || n.contains(RegExp(r'[\\/:]')))) {
    return null;
  }
  final trimmed = root.replaceFirst(RegExp(r'\\+$'), '');
  return Uri.file([trimmed, ...names].join(r'\'), windows: true);
}

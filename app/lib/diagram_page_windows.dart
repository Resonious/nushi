import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nushi/daemon.dart' show dataDir;
import 'package:nushi/diagram_page.dart';
import 'package:nushi/mermaid.dart' show cssColor;
import 'package:nushi/web_view_windows.dart';

/// The app's mermaid.html in a WebView2 of the runner's, its script the
/// pinned mermaid.min.js beside it, served from the app's assets as a host
/// of their own and nothing else: any other navigation is cancelled
/// (Mermaid's strict level has no links or clicks anyway), and a click
/// that would leave goes nowhere.
class WindowsDiagram implements DiagramHost {
  new() {
    _web.onFinished = _finished;
    unawaited(_load());
  }

  final _web = WebView2(folder: webViewFolder(dataDir), background: ground());
  bool _loaded = false;
  String? _pending; // the script to run once loaded

  Future<void> _load() async {
    if (!await _web.ready) return;
    await _web.map(diagramHost, mermaidFolder());
    await _web.load(diagramUrl);
  }

  void _finished(String url, {required bool ok}) {
    if (!ok || url != diagramUrl) return;
    _loaded = true;
    if (_pending case final js?) {
      _pending = null;
      unawaited(_web.script(js).catchError((Object _) => null));
    }
  }

  @override
  Widget view(BuildContext context) => _web.view();

  @override
  Future<void> show(
    String source, {
    required bool dark,
    required Color background,
    required Color foreground,
  }) async {
    final opts = {
      'dark': dark,
      'background': cssColor(background),
      'foreground': cssColor(foreground),
      'center': true,
    };
    // Its promise isn't a result WebView2 waits for.
    final js = 'show(${jsonEncode(source)}, ${jsonEncode(opts)}); void 0';
    if (!_loaded) {
      _pending = js;
      return;
    }
    await _web.script(js);
  }

  @override
  void dispose() {
    _pending = null;
    _web.close();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Base URL of Nushi's bundled Mermaid assets inside the Android APK.
const _mermaidBase = 'file:///android_asset/flutter_assets/assets/mermaid/';

/// Renders an agent's HTML/SVG preview or a Mermaid diagram inside a locked-down
/// Android WebView (no file/content access, no geolocation, external links sent
/// to the system browser).
Widget androidFrameView(String html, {required bool mermaid}) =>
    _AndroidPageFrame(html: html, mermaid: mermaid);

class _AndroidPageFrame extends StatefulWidget {
  const new({required this.html, required this.mermaid});

  final String html;
  final bool mermaid;

  @override
  State<_AndroidPageFrame> createState() => _AndroidPageFrameState();
}

class _AndroidPageFrameState extends State<_AndroidPageFrame> {
  late final AndroidWebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AndroidWebViewController(
      AndroidWebViewControllerCreationParams(),
    );
    final cookies = AndroidWebViewCookieManager(
      const PlatformWebViewCookieManagerCreationParams(),
    );
    unawaited(cookies.clearCookies());
    unawaited(cookies.setAcceptThirdPartyCookies(_controller, false));
    unawaited(_controller.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(_controller.setAllowFileAccess(false));
    unawaited(_controller.setAllowContentAccess(false));
    unawaited(_controller.setGeolocationEnabled(false));
    unawaited(
      _controller.setBackgroundColor(
        // design: web pages expect white paper; Mermaid paints its own ground.
        widget.mermaid ? Colors.transparent : Colors.white,
      ),
    );
    final nav = AndroidNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    unawaited(
      nav.setOnNavigationRequest((request) {
        final url = request.url;
        if (url == 'about:blank' || url.startsWith('data:')) {
          return NavigationDecision.navigate;
        }
        if (widget.mermaid && url.startsWith(_mermaidBase)) {
          return NavigationDecision.navigate;
        }
        final uri = Uri.tryParse(url);
        if (request.isMainFrame &&
            uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https')) {
          unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
        }
        return NavigationDecision.prevent;
      }),
    );
    unawaited(_controller.setPlatformNavigationDelegate(nav));
    unawaited(_load());
  }

  Future<void> _load() {
    if (widget.mermaid) {
      final resolved = widget.html.replaceFirst(
        '<base href="assets/assets/mermaid/">',
        '<base href="$_mermaidBase">',
      );
      return _controller.loadHtmlString(resolved, baseUrl: _mermaidBase);
    }
    return _controller.loadHtmlString(widget.html);
  }

  @override
  void didUpdateWidget(_AndroidPageFrame old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html || old.mermaid != widget.mermaid) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    unawaited(_controller.loadHtmlString(''));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AndroidWebViewWidget(
    AndroidWebViewWidgetCreationParams(controller: _controller),
  ).build(context);
}

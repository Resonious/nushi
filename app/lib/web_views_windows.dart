import 'package:nushi/browser_page.dart';
import 'package:nushi/diagram_page.dart';
import 'package:nushi/diagram_page_windows.dart';
import 'package:nushi/outside_page.dart';
import 'package:nushi/preview_entry.dart';
import 'package:nushi/shell_windows.dart';
import 'package:nushi/web_page.dart';
import 'package:nushi/web_page_windows.dart';
import 'package:nushi/web_views.dart';

/// Windows's web views (ADR 0125, 0134): a file's preview and a Mermaid
/// file's diagram show in WebView2s of the runner's
/// (`web_page_windows.dart`, `diagram_page_windows.dart`); a browser tab
/// is still a placeholder (`outside_page.dart`) whose button opens the
/// page in the default browser, and so is a preview without the WebView2
/// runtime. That browser is the program Windows associates with https,
/// given the address itself, so a `file:` page is shown by the browser,
/// never run by the program its type has (as on the Mac and Linux).
class WindowsWebViews implements WebViews {
  const new();

  /// Not yet: browser tabs open outside, so a link does too (ADR 0134).
  @override
  bool get embedded => false;

  @override
  PageHost page() => WindowsPage();

  @override
  BrowserHost tab(BrowserTab tab) => OutsideTab(tab);

  @override
  DiagramHost diagram() => WindowsDiagram();

  /// Only http, https and file, as the Mac's and Linux's.
  @override
  Future<void> openWithBrowser(Uri url) async {
    if (!const {'http', 'https', 'file'}.contains(url.scheme)) {
      throw const BrowserError('Couldn’t open your browser: refused');
    }
    final browser = associated('https', AssocWhat.executable, scheme: true);
    if (browser == null) {
      throw const BrowserError(
        'No default browser is set: choose one in your system’s settings.',
      );
    }
    try {
      await startOutside(browser, ['$url']);
    } on Object catch (e) {
      throw BrowserError('Couldn’t open your browser: $e');
    }
  }

  /// A mailto: address alone, handed to Explorer, which opens it with the
  /// app Windows has for mailto: (a mail app's command line is its own,
  /// unlike a browser's).
  @override
  Future<void> openMail(Uri url) async {
    if (url.scheme != 'mailto') {
      throw const BrowserError('Couldn’t open your mail app: refused');
    }
    if (associated('mailto', AssocWhat.executable, scheme: true) == null) {
      throw const BrowserError(
        'No default mail app is set: choose one in your system’s settings.',
      );
    }
    try {
      await startOutside(systemProgram('explorer.exe'), ['$url']);
    } on Object catch (e) {
      throw BrowserError('Couldn’t open your mail app: $e');
    }
  }

  /// The browser, as [openWithBrowser], for http and https alone.
  @override
  Future<void> openLink(Uri url) async {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw const BrowserError('Only a web link opens in the browser.');
    }
    await openWithBrowser(url);
  }

  /// No web view takes presses.
  @override
  Future<Duration?> sincePress({bool pointerOnly = false}) async => null;

  @override
  Future<String?> defaultBrowserName() async =>
      associated('https', AssocWhat.name, scheme: true);

  /// The browser keeps its own data.
  @override
  Future<void> clearData() async {}
}

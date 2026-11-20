import 'package:nushi/alerts_windows.dart';
import 'package:nushi/app_install_windows.dart';
import 'package:nushi/clipboard_files_windows.dart';
import 'package:nushi/conventions.dart';
import 'package:nushi/desktop_windows.dart';
import 'package:nushi/file_mode_windows.dart';
import 'package:nushi/fonts_windows.dart';
import 'package:nushi/login_item_windows.dart';
import 'package:nushi/mermaid_windows.dart';
import 'package:nushi/native.dart';
import 'package:nushi/speller_windows.dart';
import 'package:nushi/web_views_windows.dart';
import 'package:nushi/window_drag_windows.dart';

/// Windows's implementation of each native capability (ADR 0125, 0134):
/// Explorer, the shell's associations, the clipboard and the spell checker
/// (none without a dictionary for the user's language) through FFI; a
/// preview's page and the diagrams in WebView2s through the runner's
/// channel, a browser tab still a placeholder; notifications and Start at
/// login do nothing for now.
Native windowsNative() => Native(
  alerts: const WindowsAlertCenter(),
  clipboard: const WindowsClipboardFiles(),
  conventions: windowsConventions,
  desktop: const WindowsDesktop(),
  diagrams: const WindowsDiagrams(),
  fileModes: const WindowsFileModes(),
  fonts: const WindowsFonts(),
  install: WindowsAppInstall(),
  loginItem: const WindowsLoginItem(),
  speller: WindowsSpeller.open(),
  web: const WindowsWebViews(),
  window: const WindowsWindow(),
);

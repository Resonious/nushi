# 0125. The app runs on Windows

Status: accepted, 2026-11-14. Builds on [0097](0097-native-code-behind-interfaces.md) (the seams), [0104](0104-the-app-runs-on-linux.md) (the Linux app) and [0124](0124-the-daemon-builds-on-windows.md) (the daemon on Windows). Amends [0121](0121-type-to-write.md) (type to write): on Windows a character typed with Control and Alt (AltGr) goes into the box.

## Context
The daemon builds and answers on Windows (ADR 0124). The app reaches the OS only through `Native`, a set of interfaces with one implementation per platform (ADR 0097); Linux's set made the second (ADR 0104), with a GTK runner and channels of its own. Flutter builds a Windows runner as it does a GTK one. This is the app's first phase there: it builds, starts its daemon, and shows and runs chats; what each capability needs from Windows comes after.

## Decision
- **Runner**: `flutter create`'s `app/windows`, titled Nushi at 1280×800, with the system's title bar (as on Linux: headers don't move the window, no menu bar) and no channel of its own: what a capability needs from Windows is a call through `dart:ffi` or a system program, so the runner stays as generated, but for its icon, the Mac's and Linux's art at Windows's sizes in one `.ico` (`make icons`).
- **Files**: a `<capability>_windows.dart` for each capability and `native_windows.dart` for the set, which `main.dart` picks with `Platform.isWindows`; `tools/native-edge` takes `_windows.dart` files as it does `_macos.dart` and `_linux.dart`.
- **Install**: the daemon is `nushid.exe` beside `nushi.exe`, started on its own (detached, its stderr read into `app.log`: why it won't start, before it has a log) with `launchEnvironment`, Linux's too, and no login shell; the data folder is the daemon's own rule (`%LOCALAPPDATA%\Nushi`); the version is Flutter's `version.json`. Stop does nothing yet: a Windows Unix socket doesn't name the process at its other end, so the app can't tell which daemon listens, and says to end `nushid.exe` in Task Manager; so nothing offers Restart daemon there (`AppInstall.canStop`), and a daemon too old to restart itself says how to end it.
- **The desktop**: Show in Explorer is shell32's `SHOpenFolderAndSelectItems` through FFI (`explorer.exe /select,<path>` splits a path at a comma), a folder opens in Explorer, a file as text in what `.txt` opens (else Notepad), a page in the program `https` opens, mail through `mailto` and Explorer; what a scheme or an extension opens is shlwapi's `AssocQueryStringW`. A system program is named by its full path under `%SystemRoot%`, and every program starts on its own with the app's environment less Nushi's own variables, as on Linux.
- **Fonts**: every family is the registry's font list's (`reg query` of the machine's and the user's `Fonts` keys, a face's Bold and Italic its family's); the monospaced ones are those of a few known families whose files are installed.
- **Conventions**: Control for ⌘, "Show in Explorer", Credential Manager, the taskbar's badge. No key holds Control and Alt: Windows reports AltGr as both (and takes Ctrl+Alt for it), which types `@`, `#` and `|` on Spanish, French and Belgian keyboards, so the chat's tabs (Linux's Ctrl+Alt+1–3) are Ctrl+Shift+1–3 (`Cmd.windows`, `Conventions.altGr`), and a character typed with both goes into the chat's box as any other (ADR 0121).
- **Off on Windows** for now, each a stand-in: notifications, the clipboard's files, Start at login, web views (WebView2) and so Mermaid's diagrams (their source shows), spell check, the back swipe, and presenting the window.

## Consequences
- `flutter build windows` builds `nushi.exe` (Developer Mode must be on: Flutter's plugins are linked by symlink), and with `nushid.exe` beside it the app starts its daemon and runs chats. There's no package or installer yet, and CI doesn't build it.
- A program started by a packaged (MSIX) app, such as a desktop app's terminal, has its `AppData` writes redirected into that app's package folder, and a Unix socket made there can't be connected to: the app reports the daemon not answering. Start Nushi from Explorer or a shell of your own (docs/development.md).

## Alternatives considered
- A channel in the runner for each capability, as Linux's GTK runner has: C++ to build and test for what FFI and a system program do now. A capability that needs a COM object or a window message (notifications, WebView2) may bring one.
- A drawn title bar (`window_manager`): the system's is what Linux keeps too, and it moves, snaps and zooms as Windows users expect.
- WebView2 now: a plugin and its runtime for pages and diagrams, the largest piece left; the placeholder that opens a page in the browser stands in, as it did on Linux at first.

**Amendment (2026-11-20): `AppInstall.canStop` is gone.** Windows stops its daemon by the stop event its pid names ([ADR 0134](0134-the-apps-capabilities-on-windows.md)), so every platform's install stops the daemon and the flag answered true everywhere. Restart daemon is offered wherever the app has a packaged daemon (`restartsDaemon`); a daemon that doesn't stop when asked still says how to end it by hand (`stopByHand`).

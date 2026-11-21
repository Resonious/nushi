# 0070. Preview tabs are the pane's own, not the chat header's

Status: accepted, 2026-10-31.

## Context
The owner wants to look at more than one file at a time. A first build (3b39a57, 6bc6aa3, 16a4751, never released) put each file in the chat header as a closable segment beside Chat and Changes, with the file in the whole main area. The owner rejected it: "Those tabs look horrible", "It just pushes the other panes around". A redesign with a permanent side column was rejected too. Their answer: "the panel that you use to view the [file] could just show tabs if you preview multiple files."

## Decision
- **The tabs live in the preview pane's title row.** With one file the pane is what it always was. With two or more, the file name in that row becomes the row of tabs, in the same slot: no new row, so the pane's height and everything else on screen stay put. The header's tabs stay Chat, Changes and Pull request.
- **Plain names, not controls.** The showing tab is the primary text with a thin line under it, the others muted, a ✕ always on the showing tab and on the others under the pointer. No pill, segmented control or box. Past the room the widest shrink, with an ellipsis, to a least width, then the row scrolls. No overflow menu.
- **Every open is a tab.** A click in the chat, the Files list, ⌘P and the agent's `show` all go through `ChatState.openPreview`, which adds a tab or shows the one the file has, matched by absolute path. `show` keeps ADR 0068's rules: it opens only on the Chat tab, and only where the pane fits. There's no ⌘-click and no second kind of opening.
- **Tabs are the pane's life.** In memory, as the preview always was: never saved, cleared when the pane closes by its Close, by its last tab, or by a subagent's or command's pane taking its place. The pane keeps its one remembered width.
- **One view at a time.** A file's view is made again when its tab shows, with no keep-alive, so a page costs a web view only while it's seen. Its Source or Preview is remembered per file while the app runs.
- **⌘W closes the showing tab** while the pane is in sight (File › Close Tab, the way out of a web page). A focused terminal keeps ⌘W, and a dialog's is left alone.

## Consequences
- With tabs up, the name's menu of the chat's other files isn't in the row; the Artifacts widget, Artifacts… and ⌘P remain.
- Amended 2026-11-05: the menu is gone with one file open too. The owner: "this dropdown here I don't think makes sense". Tabs, the Files pane (ADR 0090), ⌘P and the Artifacts widget (with its pins) open every file it listed, and a menu on the name was a second way to switch that worked only with one file open. The name is plain text, its path in a tooltip; a click shows the file in the Files pane, folders above it opened, when it's in the chat's folder.
- Amended by [0094](0094-browser-tabs-for-local-web-servers.md): a tab is a file or a browser tab (`PreviewEntry`), in one row in the order opened. A browser tab is a page, not a file, so it gets what a file's tab doesn't: a + at the row's end, shown only while a browser tab shows, opens a new one (a second way to open, for what has no other: the header's globe and the palette's New browser tab are the rest). Files keep plain-name tabs and no other control. One view at a time holds for both: a browser tab's page loads again when it shows.
- Tabs live only in the pane's width, so they can't give a file the whole window. That went with the header tabs, along with their keys (⌃⌘4–9), restored tabs across launches, and the pane's Open in a tab.
- The phone is unchanged: its previews are full screen.

## Alternatives considered
- Tabs in the chat header: rejected by the owner, above.
- A permanent side column of open files: rejected by the owner; it takes room from every view for a list that's usually one file.
- A second row under the pane's title: it would change the pane's height with the number of files, moving what's under it.
- An overflow menu for what doesn't fit: more controls in a thin row, for what scrolling already does.

**Amendment (2026-11-15):** the preview pane runs the chat pane's full height, right of the details panel, so its title row with the tabs is level with the chat's header, the window's top row, not under it ([ADR 0123](0123-side-panes-right-of-the-rail.md)). Still one row.

**Amendment (2026-11-15): the tabs are the Files pane's** ([ADR 0123](0123-side-panes-right-of-the-rail.md)'s amendment). The file view is the Files pane's viewer, and its row is the pane's top row, which says Files at its left: the one file's name, or the tabs, come after Files rather than in a title's place, since the pane is Files, not one file. The one file's name has its tab's ✕ after it, as the pane's × now hides Files (keeping the tabs, as ⇧⌘E does) rather than closing the files. The last file closed, with its ✕ or ⌘W, leaves the viewer blank and the pane open. Browser tabs are the browser pane's own (ADR 0094); every way of opening a file opens the Files pane on it (`openInFiles`).

**Amendment (2026-11-16): preview tabs, a second kind of open, switchable** (Claude desktop's Files ⋯ has Preview tabs, on, as VS Code's). With **Preview tabs** on (the default; `previewTabs`, the Files pane's ⋯, View › Use Preview Tabs, the palette), a click on a file in the Files pane's tree opens a provisional tab, its name in italics (measured so): the next click's file takes its place, in its slot, until it's kept. A double click (on its row, its tab or the one file's name), its first unsaved edit, a pin, ⏎ on its row and every other way of opening it (the conversation, ⌘P, `show`, Artifacts) keep it; there's at most one. The tree's click still opens at once: the second click is told by a timer as Flutter's double tap is, beside the tap, not by waiting. Off, every open keeps its tab; the one provisional then stays so until kept. "No second kind of opening" above holds for every way in but the tree's click.

**Amendment (2026-11-19): the file tabs are kept across launches**, on the owner's word ("when resetting Nushi for updates it doesn't open back up the file I had been looking at"), reversing "never saved" above. `app.json`'s `fileTabs` keeps each chat's tabs by chat id (`fileTabsKept`, `files_kept.dart`): their names in order, relative to the chat's folder when inside it so a moved folder still finds them, the one showing, the provisional one and those showing their Source. Not scroll positions, nor unsaved edits, which still last only while the app runs. At launch, as the daemon first lists the chat, the daemon is asked which are still files the pane can open (FindChatFiles); a gone one doesn't come back, and in place of a gone one that showed, the next one left shows, else the last; with none left the pane is as it is with no tabs. A deleted chat's are dropped with its other prefs. Browser tabs aren't kept.

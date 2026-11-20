# 0143. A page finds with a script of its own

Status: accepted, 2026-11-20 (#63).

## Context
⌘F found only in the chat, Changes, a terminal and the editor. Previews drawn by Flutter (rendered Markdown, a read-only source, a CSV's table) can use the transcript's find as it is. An HTML page and a browser tab are web views, whose text Flutter can't see, and the find bar must look and count as everywhere else ("2 of 7", the theme's colours). WebKit's own find (`WKWebView.find`, macOS 13) selects one match at a time and gives no count; it would mark the current match in the system's selection colour and nothing else.

## Decision
- **A page's find is a script** the web view runs in a content world of Nushi's own (`WKContentWorld.defaultClient`, `PageFind` in `MainFlutterWindow.swift`), with the query and colours as arguments, never pasted into its text: the page's scripts can't see its variables or replace the functions it calls. It reads the page's visible text (not scripts, styles, form fields or what's hidden), case aside, a match may cross inline elements but not two blocks, and it counts them, 10,000 at most.
- **Matches are marked with the CSS Custom Highlight API** (`CSS.highlights`), in a style sheet adopted for the purpose (a `<style>` only where that fails): the page's DOM and text stay as they were, a selection or a copy is the page's own, and a page's Content Security Policy doesn't stop it (tried with `style-src 'none'`). The current match is in the accent with an underline in its edge colour, since a highlight can't draw a border.
- **⌘F reaches the find** from the menu bar while WebKit has the keys: the app's action asks each page shown whether its web view is the first responder. Esc clears the marks and gives the keys back to where they were as the bar opened: the web view when ⌘F came from it, else the Flutter field that had them (a browser tab's address field). A page that loads again is looked in again.
- **The Mac only.** Linux has no web view (ADR 0104). Windows's WebView2 page could run the same script, but its `ExecuteScript` runs in the page's own world, and how ⌘F reaches the app while WebView2 has the keys is untried; until it's built and tried on Windows, its page has no find rather than a broken one. Its browser tabs open in the default browser anyway (ADR 0134). A page's host says whether it has a find (`PageHost.finder`, `BrowserHost.finder`); SVG, PDF and diagram previews have none.

## Consequences
The page can see the highlights' names in `CSS.highlights` and, through their ranges, what's searched for; nothing else of Nushi's. A page that changes after the find marks what it found then until the query changes or the page loads again.

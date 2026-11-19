# 0087. Settings is a modal over the window

## Context
ADR 0053 made Settings a view in the chat's place, so its pages had room. With themes (ADR 0086) a pick should be judged on the app itself, and Settings in the chat's place hid the very chat a theme repaints. The owner: "I'm thinking we should make the settings a modal instead."

## Decision
- **Settings opens over the window**, which stays in sight, dimmed, behind it: about 960×720 at most, centered, 40 px from the window's edges when the window is smaller; the same nav of sections and pages (`settings_rows.dart`'s layout, ADR 0053's), under a title bar with Close. A theme picked repaints the app behind it at once.
- **It's state, not a place**: `Daemon.settingsOpen` (its section and the agent Agents marks), beside `place`, which it never changes. Closing it (Esc, Close, ⌘, again, a click on the dim) leaves the window as it was, the focus back where it was. Every way in is still `Daemon.openSettings(section:, folder:, agent:)`; the sidebar's Settings row opens it and is never marked as the place.
- **Nothing behind it takes keys or focus** while it's open: the app behind is out of focus traversal, and the app's own keys (⌘K, ⌘N, ⌘1–⌘9…) stop at the modal, but ⌘,. A menu bar item, or anything in Settings that starts work elsewhere (a chat from a skill, a chat's copy opened from Chat history, a trust card asking), shuts it first; going to a place or picking a chat does too. A sheet opened from a page (Set up, Add server) is a dialog over the modal and keeps it.

## Consequences
- A page has about 700 px for its content at most, less in a small window: pages are laid out for that width (Appearance's cards are three across at most).
- ADR 0053's "Esc goes back to what showed before" is the modal's own: nothing in the main area moved.
- The window's size no longer sets Settings' size; a long page scrolls inside the modal.

## Alternatives considered
- Keep Settings in the chat's place: a theme can't be judged on the chat it repaints.
- A separate window (macOS's usual Settings window): ADR 0053's reasons stand (focus moving between windows on every deep link).
- A modal route on the navigator: its open and closed state would live beside the daemon's and the deep links that switch a page while it's open would have to reach into the route.

## Amendment (2026-11-19): it grows with the window, one title, a grouped nav
- **Its size follows the window**: 40 px in from each edge, as before, but up to 1120 wide (past that a page's column, 740 at most, would only leave space) and as tall as the window lets it, not 960×720. At 1700×1000 it was about 40% of the window, and long pages scrolled inside a small box.
- **One title**: the bar that said "Settings" over the page's own title is gone. "Settings" heads the nav; the page's name is the page's title; Close (Esc) sits in the page's top right corner, and a title's actions keep clear of it.
- **The nav is grouped**: App (General, Appearance, Terminal), Agents (Agents, MCP servers, Skills, Chat history), Connections (GitHub, Jira, Remote access), then Logs & advanced set apart. A connection with an account that works (a GitHub host signed in, a Jira site without a problem) has a solid dot in the done color, asked of the daemon as Settings opens and kept as its page lists them.
- The direction picked of three mocked ("Tidy modal", the owner: "it's easier and looks good"); the other two, one searchable page and Settings in the main area, were larger changes, the second undoing this ADR.


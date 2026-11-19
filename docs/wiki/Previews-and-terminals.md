# Previews and terminals

When the agent writes a file, such as a report, a web page or a diagram, you can see it right next to the chat, and it updates as the agent changes it. Each chat can also have its own terminals, so you can run commands in the chat's folder without leaving Nushi.

Shortcuts below are the Mac's. On Linux, use Ctrl where the Mac uses ⌘, and Alt where it uses ⌥. Terminals use different keys on Linux; they're given where they come up.

![A Markdown design note previewed beside the chat that wrote it](https://raw.githubusercontent.com/afrase/nushi/main/docs/images/preview.png)

## Open a file

When the agent writes a document, page, image or diagram, its row in the chat has a **Preview** button. Click it and the file opens in the **Files** pane beside the chat, right of the details panel, from the window's top to its bottom (in a narrow window it lies over the chat's right side instead). Where the row is narrow (a subagent's pane), the button is inside the row: click the row to open it first.

You can also open files in these ways:

- **Artifacts**: in the details panel (the panel button in the chat's header), the **Artifacts** list shows the documents, pages and images the chat made. Click one to open it.
- **Open file** (⌘P): type part of a name to open any file in the chat's folder, code included.
- **Files** (⇧⌘E, or the folder button in the header): the open files on the left and a tree of the chat's folder on the right, as in Claude's desktop app. With nothing open it says **Open files appear here**. Files with changes have a dot (below). Opening a file never moves the tree. Type in **Search files…** above the tree to find a file anywhere in the folder. The three buttons at the right of the pane's second row collapse every folder, hide or show the tree (⇧⌘Y; the open file takes its room) and open **⋯**, which has **Go to file or search** (⌘P), **File tree position** (put the tree on the left or the right; Automatic keeps it at the window's edge), **Preview tabs** and how a file's source shows: **Word wrap**, **Indent guides**, **Show whitespace**, **Scroll past end** and **Tab size** (2, 4 or 8 columns).

Some agents can also open a file in the Files pane, or a page on your own machine in the browser, themselves.

## What you can preview

- **Markdown**, rendered. Long documents get a small outline on the left; point at it to jump to a heading.
- **HTML pages and SVG**, shown as a web page. Use **Reload**, or **Open in browser** to view it in your normal browser.
- **Images** and **PDFs**.
- **CSV files**, as a table (the first 500 rows).
- **Mermaid diagrams** (`.mmd` or `.mermaid` files). Mermaid blocks in the agent's messages draw as diagrams too.
- **Code and text files**, with syntax highlighting.

Above the file, in the pane's second row, is its path. Click the path to copy it.

## See which lines changed

A file's code shows which lines the chat changed, committed or not, so you can see what the agent changed without opening a diff. On a branch of its own, they're the same changes the **Changes** tab's **Branch** view shows, so they stay after the agent commits. A chat working straight on the main branch is marked from before its own commits (the commits made since the chat began), or against the last commit when it hasn't committed. Beside the line numbers, a green bar marks added lines, a blue bar changed lines, and a small red wedge the place where lines were removed. The marks follow what you type, too.

Next to the file's path, a pill says what the marks count from and how many lines changed: **5 changed lines since main**, **since this chat began** or **since the last commit**. A new file says **New file**, and every line has the green bar.

1. Point at a mark, or click it, to see what those lines were: **Before this branch**, **Before this chat**, or **Before** when it's the last commit.
2. Click elsewhere to close it.
3. For the full diff, right-click a file with a dot in the tree and pick **Show changes**: it opens in the chat's **Changes** tab.

Rendered views (Markdown, CSV, HTML) can't show marks: click the pill (**3 changed lines since main ›**) to switch to the source, where they are.

In the tree, a green dot marks every file with changes (the ones that open with marks or **New file**), whoever made them: the agent, a command, or you. The folders holding one have it too, even closed. A file the chat wrote back as it was has none (opened, it says **No changes since main**). In a folder that isn't a git repository there's nothing to compare with, so the dot marks the files the chat wrote instead.

A file with a dot and no marks always says why next to its path: **Not in a git repository**, **Ignored by git**, a link, not text, too large or over 10,000 lines, **Change marks need a newer daemon** (restart Nushi), or **Couldn’t compare with git** (click it for git's words). A file outside the chat's folder is marked against its own last commit.

## Work with several files

Opening a second file adds a tab at the top of the Files pane, after **Files**. A click in the tree opens the file in an *italic* tab that the next click's file replaces, so looking through files doesn't fill the row; double-click it, edit it or pin it to keep it. Turn **Preview tabs** off in the pane's **⋯** to keep every file you click.

- Click a name to switch to that file.
- Click a tab's **✕**, or press ⌘W, to close it. Closing the last one leaves the pane open and blank.
- The pane's **×** (or ⇧⌘E) hides it; your open files are still there when it comes back.
- **Expand** gives the pane the whole chat area, and **Collapse** (or Esc) gives the chat back.

## Edit a file

You can edit any file that shows as text. For Markdown, HTML, SVG, CSV and diagrams, first click the **`</>`** button after the path (**View source**). Click **View preview** to go back.

1. Click in the text and type. There's no Edit button.
2. Press ⌘S to save. Clicking into the message box or a terminal saves too.

A dot by the file's name means unsaved changes. With your next message, the agent is told you edited the file.

If the agent changes the lines you're editing, you'll see **Changed on disk**, with **Compare**, **Overwrite with mine** and **Use theirs**.

## Right-click in a file

Right-click in a file's text in the Files pane for an editor's menu.

- **Copy**: the selected text.
- **Copy path**: the file's path with a line, as `docs/roadmap.md:12`: the selection's first line, or the line you clicked.
- **Quote in reply**: the selected lines go into the chat's message box as a quote, with the file and line numbers. Type your message under it and send.
- **Find…** (⌘F): find in the file, while you're editing it.
- **Show in Finder** (Show in Folder on Linux, Show in Explorer on Windows) and **Open in your editor**, your default text editor.

While you're editing, **Cut** and **Paste** are there too. Copy, Cut and Quote in reply need a selection. Right-clicking keeps your selection where it is.

## Use the browser

A browser tab shows a web page beside the chat, such as the dev server the agent just started.

1. Click the globe in the chat's header (**Show browser**), or choose **New browser tab** from the palette (⌘K).
2. Type an address and press Return. `localhost:3000`, or just `3000`, works for a local server.

The browser's tabs sit in its top row, level with the chat's header; the bar under them has Back, Forward and Reload (⌘R). ⌘L jumps to the address field. **Expand** gives the browser the whole chat area, its header and terminal too, and **Collapse** (or Esc) gives the chat back.

**When the window gets narrow.** Panes open right of the details panel, and the header's buttons move left to make room. When the panes would leave the chat too narrow, the details panel tucks itself away; it comes back by itself as soon as there's room (a wider window, a narrower or closed pane). Its button stays lit, since you still want it: press it to hide the panel for good. Narrower still, the panes get narrower, the widest first, so the chat keeps its room (in the Files pane, the open file gives first, then the tree); the widths you dragged them to come back once there's room. Only when every pane is as narrow as it goes do they lie over the chat's right side, still from the window's top to its bottom. In a very narrow window the panel can't show at all, and its button is off.

If your project lists dev servers in a launch file (`.claude/launch.json` or `.agents/launch.json`), the **Servers** button starts and stops them. **Logs** shows a server's output. A server marked **Agent can't name it** has a name the agent can't use (only letters, digits and `: _ . -`): start it from the menu, or rename it in the launch file.

## Open a terminal

Each chat has its own terminals, in tabs under the chat. They start in the chat's folder, using your normal login shell (on Windows, the shell Windows Terminal opens by default).

1. Click the terminal button in the chat's header, or press ⌃\`.
2. Press ⌘T (Ctrl+Shift+T on Linux), or click the **+** after the tabs, for another terminal.
3. Press ⌘W (Ctrl+Shift+W on Linux) to close the terminal you're in. Press ⌃\` again to hide the panel.

Terminals keep running after you quit the app, because Nushi's background service (the daemon) keeps them. Reopen the app and they're still there.

![A terminal under a chat, showing a test run](https://raw.githubusercontent.com/afrase/nushi/main/docs/images/terminal.png)

## Run a command from the chat

When the agent suggests a shell command in a code block, click **▷** next to the copy button. Nushi types it into one of the chat's terminals for you. When it finishes, a card with the output appears in the message box, and goes to the agent with your next message. To leave it out, point at the card and click its **✕**.

## Good to know

- ⌥⌘1 to ⌥⌘9 switch between terminals, and ⌘F searches a terminal's scrollback. On Linux, use Alt+1 to Alt+9 and Ctrl+Shift+F.
- Restarting the daemon closes your terminals. Archiving or deleting a chat closes its terminals too.
- On Linux, HTML pages, SVG, PDFs and browser tabs show a placeholder with an **Open in** button for your default browser. Mermaid diagrams show as source, in files and in messages.
- Some files are read-only in the Files pane, for example files over 1 MB or files you don't have permission to write. The reason shows above the text.
- ⌥Z turns line wrapping on or off in a code preview.
- On the [Phone](Phone), previews open full screen, with no tabs and no editing.

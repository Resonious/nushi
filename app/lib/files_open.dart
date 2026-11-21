import 'package:nushi/chat.dart';
import 'package:nushi/settings.dart';

// Whether a chat's Files pane is open, and opening or closing it: the
// header's button, ⇧⌘E, View › Files, and every way a file opens.

/// Opens [chat]'s Files pane, or closes it (keeping its file tabs): the
/// pane's own way.
void toggleFiles(ChatState chat) {
  final open = {...filesChats.value};
  if (!open.remove(chat.id)) open.add(chat.id);
  filesChats.value = open;
}

/// Whether [chat]'s Files pane is open: `filesChats` tells when it changes.
bool filesOpen(ChatState chat) => filesChats.value.contains(chat.id);

/// Whether [chat]'s Files pane shows: open, on the Chat tab (it's beside
/// the chat).
bool filesShown(ChatState chat) =>
    filesOpen(chat) && chat.shownTab == ChatTab.chat;

/// Hides [chat]'s Files pane while it shows, or shows it, on the Chat tab:
/// what ⇧⌘E, View › Files, the header's button and the pane's × do. Its
/// file tabs stay either way.
void showOrHideFiles(ChatState chat) {
  if (filesShown(chat)) return toggleFiles(chat);
  chat.tab.value = ChatTab.chat;
  if (!filesOpen(chat)) toggleFiles(chat);
}

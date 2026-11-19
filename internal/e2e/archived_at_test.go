package e2e

import (
	"context"
	"testing"

	"connectrpc.com/connect"

	"github.com/afrase/nushi/internal/acptest"
	nushiv1 "github.com/afrase/nushi/internal/gen/nushi/v1"
)

// A chat says when it was archived (archived_unix_ms): set by archiving,
// kept by archiving it again, cleared by unarchiving and set anew by the
// next archive; kept across a restart.
func TestArchivedUnixMs(t *testing.T) {
	ctx := context.Background()
	dataDir, history := t.TempDir(), &acptest.History{}
	d := startDaemon(t, dataDir, history)
	a := open(t, d)
	at := func(id string) int64 {
		t.Helper()
		for _, c := range must(a.c.ListChats(ctx, connect.NewRequest(&nushiv1.ListChatsRequest{}))).Chats {
			if c.Id == id {
				return c.ArchivedUnixMs
			}
		}
		t.Fatalf("no chat %s", id)
		return 0
	}
	archive := func(id string, archived bool) {
		t.Helper()
		must(a.c.ArchiveChat(ctx, connect.NewRequest(&nushiv1.ArchiveChatRequest{ChatId: id, Archived: archived})))
	}
	x := a.start(&nushiv1.StartChatRequest{Folder: t.TempDir()})
	if got := at(x); got != 0 {
		t.Fatalf("not archived: %d", got)
	}

	archive(x, true)
	first := at(x)
	if first == 0 {
		t.Fatal("archived without a time")
	}
	archive(x, true)
	if got := at(x); got != first {
		t.Fatalf("archived again: %d, want %d", got, first)
	}

	archive(x, false)
	if got := at(x); got != 0 {
		t.Fatalf("unarchived: %d", got)
	}
	// Archiving waits out the reopen the unarchive began.
	until(t, "the chat to archive again", func() bool {
		_, err := a.c.ArchiveChat(ctx, connect.NewRequest(&nushiv1.ArchiveChatRequest{ChatId: x, Archived: true}))
		return err == nil
	})
	second := at(x)
	if second < first {
		t.Fatalf("archived anew: %d, before %d", second, first)
	}

	d.stop()
	d = startDaemon(t, dataDir, history)
	a = open(t, d)
	if got := at(x); got != second {
		t.Fatalf("after a restart: %d, want %d", got, second)
	}
}

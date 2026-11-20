package e2e

import (
	"context"
	"testing"

	"connectrpc.com/connect"

	"github.com/afrase/nushi/internal/acptest"
	nushiv1 "github.com/afrase/nushi/internal/gen/nushi/v1"
)

// The Mac's find counts a query's matches in a chat's items before the
// part it has loaded, case aside; a phone may not ask (it has no find).
func TestFindInChat(t *testing.T) {
	ctx := context.Background()
	d := startDaemon(t, t.TempDir(), &acptest.History{})
	mac := open(t, d)
	id := mac.start(&nushiv1.StartChatRequest{Folder: t.TempDir()})
	for _, p := range []string{"a Needle", "hay", "needle, NEEDLE", "hay"} {
		mac.say(id, p)
	}
	all := mac.get(id)
	find := func(before string) []*nushiv1.ChatMatch {
		return must(mac.c.FindInChat(ctx, connect.NewRequest(&nushiv1.FindInChatRequest{ChatId: id, Text: "needle", Before: before}))).Matches
	}
	whole := find("")
	// The fake agent says each prompt back: each match twice.
	if len(whole) != 4 || whole[0].Count != 1 || whole[2].Count != 2 || whole[3].Count != 2 {
		t.Fatalf("the whole chat: %v", whole)
	}
	at := 0
	for i, it := range all.Items {
		if it.Id == whole[2].ItemId {
			at = i
		}
	}
	if got := find(all.Items[at].Id); len(got) != 2 || got[1].ItemId != whole[1].ItemId {
		t.Errorf("before the third: %v", got)
	}
	if _, err := mac.c.FindInChat(ctx, connect.NewRequest(&nushiv1.FindInChatRequest{ChatId: id, Text: "x", Before: "gone"})); connect.CodeOf(err) != connect.CodeNotFound {
		t.Errorf("before an unknown item: %v", err)
	}
	phone := openAt(t, d.devices)
	if _, err := phone.c.FindInChat(ctx, connect.NewRequest(&nushiv1.FindInChatRequest{ChatId: id, Text: "needle"})); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Errorf("a phone's find: %v", err)
	}
}

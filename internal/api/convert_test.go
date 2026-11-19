package api

import (
	"testing"
	"time"

	"github.com/afrase/nushi/internal/model"
)

// A chat's archive time goes out in Unix milliseconds; one archived
// before the daemon kept the time, or not archived, says 0.
func TestChatProtoArchivedAt(t *testing.T) {
	at := time.UnixMilli(1_700_000_000_123)
	for _, tc := range []struct {
		name string
		rec  model.ChatRecord
		want int64
	}{
		{"archived", model.ChatRecord{Archived: true, ArchivedAt: at}, at.UnixMilli()},
		{"archived before the time was kept", model.ChatRecord{Archived: true}, 0},
		{"not archived", model.ChatRecord{}, 0},
	} {
		if got := chatProto(tc.rec).GetArchivedUnixMs(); got != tc.want {
			t.Errorf("%s: %d, want %d", tc.name, got, tc.want)
		}
	}
}

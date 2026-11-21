package chats

import (
	"errors"
	"fmt"
	"slices"
	"testing"

	"github.com/afrase/nushi/internal/model"
	"github.com/afrase/nushi/internal/testcheck"
)

// A page reaches back to the call that started a subagent whose steps are
// in it (and to that call's own subagent's call), so subagents show whole;
// a step whose call isn't before it changes nothing.
func TestPageStart(t *testing.T) {
	items := []model.Item{{ID: "a"}, {ID: "call"}, {ID: "b", Parent: "call"}, {ID: "inner", Parent: "call"},
		{ID: "c", Parent: "inner"}, {ID: "d"}, {ID: "e", Parent: "gone"}}
	for _, tc := range []struct{ end, n, want int }{
		{7, 2, 5}, // d, e
		{7, 3, 1}, // c's subagent's call is "inner", whose is "call"
		{7, 10, 0},
		{5, 1, 1},
		{3, 1, 1},
		{4, 1, 1}, // inner's call
	} {
		if got := pageStart(items, tc.end, tc.n); got != tc.want {
			t.Errorf("pageStart(%d, %d) = %d, want %d", tc.end, tc.n, got, tc.want)
		}
	}
}

// The recent part comes with what runs or asks before it: a background
// command or subagent still running, a permission prompt or question still
// pending; not one that ended or was answered.
func TestRunningIn(t *testing.T) {
	items := []model.Item{
		{ID: "dev", BackgroundCommand: &model.BackgroundCommand{State: "running"}},
		{ID: "done", BackgroundCommand: &model.BackgroundCommand{State: "completed"}},
		{ID: "a"},
		{ID: "agent", Subagent: &model.Subagent{State: "running"}},
		{ID: "ask", Kind: model.Permission, Status: "pending"},
		{ID: "asked", Kind: model.Permission, Status: "answered"},
		{ID: "form", Kind: model.Question, Status: "pending"},
		{ID: "call", Kind: model.ToolCall, Status: "pending"},
	}
	var got []string
	for _, it := range runningIn(items) {
		got = append(got, it.ID)
	}
	if want := []string{"dev", "agent", "ask", "form"}; !slices.Equal(got, want) {
		t.Errorf("running: %v, want %v", got, want)
	}
}

// A subagent that runs beside many items doesn't bring them all into each
// page: a page reaches back maxReach items at most for a call, and one
// further back leaves the page as it is.
func TestAPageReachesBackSoFar(t *testing.T) {
	items := []model.Item{{ID: "call"}}
	for i := range 3 * maxReach {
		it := model.Item{ID: fmt.Sprint("i", i)}
		if i%10 == 0 {
			it.Parent = "call"
		}
		items = append(items, it)
	}
	end := len(items)
	if got := pageStart(items, end, 80); got != end-80 {
		t.Errorf("pageStart(%d, 80) = %d, want %d: the call is out of reach", end, got, end-80)
	}
	if got := pageStart(items, maxReach, 80); got != 0 {
		t.Errorf("a call within reach: pageStart = %d, want 0", got)
	}
}

// A background subagent's permission prompt far above a long chat's recent
// part comes with it: the chat waits on it, so its card must show.
func TestTheRecentPartBringsAPendingAsk(t *testing.T) {
	svc, _, c := newChat(t, `{"sessionId":"s1"}`, &memModes{})
	c.mu.Lock()
	c.items = []model.Item{{ID: "ask", Kind: model.Permission, Status: "pending", Parent: "sub"}}
	for i := range 300 {
		c.items = append(c.items, model.Item{ID: fmt.Sprint("i", i), Kind: model.AgentMessage, Text: "x"})
	}
	c.mu.Unlock()
	part, err := svc.Recent(c.id, 80)
	testcheck.NoErr(t, err)
	if part.Older != 221 || len(part.Running) != 1 || part.Running[0].ID != "ask" {
		t.Errorf("older %d, running %+v", part.Older, part.Running)
	}
}

// A page that reaches back to an item far above the one it ends before
// holds it and n items above it, maxThrough items at most; one already in
// the page's n changes nothing, and an item the chat hasn't is refused.
func TestAPageThroughAnItem(t *testing.T) {
	svc, _, c := newChat(t, `{"sessionId":"s1"}`, &memModes{})
	items := make([]model.Item, 3*maxThrough)
	for i := range items {
		items[i] = model.Item{ID: fmt.Sprint("i", i), Kind: model.AgentMessage, Text: "x"}
	}
	setItems(c, items)
	end := len(items) - 10
	before := items[end].ID
	for _, tc := range []struct {
		through   string
		wantStart int
	}{
		{"", end - 20},
		{items[end-5].ID, end - 20},                    // in the page already
		{items[end-500].ID, end - 520},                 // n above it
		{items[end-maxThrough+5].ID, end - maxThrough}, // its n cut at maxThrough
		{items[100].ID, end - maxThrough},              // too far: the client asks again
		{items[len(items)-1].ID, end - 20},             // after the page
	} {
		page, start, err := svc.Items(c.id, before, tc.through, 20)
		testcheck.NoErr(t, err)
		if start != tc.wantStart || len(page) != end-start || page[0].ID != items[start].ID {
			t.Errorf("through %q: start %d (%d items), want %d", tc.through, start, len(page), tc.wantStart)
		}
	}
	if _, _, err := svc.Items(c.id, before, "gone", 20); !errors.Is(err, ErrNoItem) {
		t.Errorf("through an item it hasn't: %v", err)
	}
}

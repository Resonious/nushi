package githubapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"slices"
	"sync"
	"testing"
)

func TestViewed(t *testing.T) {
	f := newFake(t)
	var (
		mu     sync.Mutex
		afters []any
	)
	f.route("graphql Viewed", func(w http.ResponseWriter, r *http.Request) {
		var q struct{ Variables map[string]any }
		_ = json.NewDecoder(r.Body).Decode(&q)
		mu.Lock()
		afters = append(afters, q.Variables["after"])
		mu.Unlock()
		if q.Variables["after"] == nil {
			_, _ = w.Write([]byte(`{"data":{"repository":{"pullRequest":{"files":{"pageInfo":{"hasNextPage":true,"endCursor":"c1"},"nodes":[` +
				`{"path":"auth/session.go","viewerViewedState":"VIEWED"},{"path":"auth/middleware.go","viewerViewedState":"UNVIEWED"}]}}}}}`))
			return
		}
		_, _ = w.Write([]byte(`{"data":{"repository":{"pullRequest":{"files":{"pageInfo":{"hasNextPage":false,"endCursor":"c2"},"nodes":[` +
			`{"path":"docs/auth.md","viewerViewedState":"DISMISSED"},{"path":"auth/session_test.go","viewerViewedState":"VIEWED"}]}}}}}`))
	})
	viewed, changed, err := f.client().Viewed(t.Context(), "acme/lumen", 218)
	if err != nil || !slices.Equal(viewed, []string{"auth/session.go", "auth/session_test.go"}) || !slices.Equal(changed, []string{"docs/auth.md"}) {
		t.Fatalf("%v %v %v", viewed, changed, err)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(afters) != 2 || afters[0] != nil || afters[1] != "c1" {
		t.Fatalf("pages asked: %v", afters)
	}
	if _, _, err := f.client().Viewed(t.Context(), "not a repo", 1); err == nil {
		t.Fatal("a bad repository's name")
	}
	f.route("graphql Viewed", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"data":{"repository":{"pullRequest":null}}}`))
	})
	if _, _, err := f.client().Viewed(t.Context(), "acme/lumen", 9); !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
}

func TestSetViewed(t *testing.T) {
	f := newFake(t)
	mark := f.vars("MarkViewed", `{"data":{"markFileAsViewed":{"clientMutationId":null}}}`)
	unmark := f.vars("UnmarkViewed", `{"data":{"unmarkFileAsViewed":{"clientMutationId":null}}}`)
	c := f.client()
	if err := c.SetViewed(t.Context(), "PR_218", "auth/session.go", true); err != nil || (*mark)[0]["pull"] != "PR_218" || (*mark)[0]["path"] != "auth/session.go" {
		t.Fatal(err, *mark)
	}
	if err := c.SetViewed(t.Context(), "PR_218", "auth/session.go", false); err != nil || len(*unmark) != 1 {
		t.Fatal(err, *unmark)
	}
	if err := c.SetViewed(t.Context(), "PR_218", "", true); err == nil {
		t.Fatal("no file")
	}
}

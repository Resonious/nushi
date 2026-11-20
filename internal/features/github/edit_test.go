package github

import (
	"errors"
	"testing"

	"github.com/afrase/nushi/internal/model"
)

// editable is mira's pull request on acme/lumen, which the user may edit.
func editable() model.GitHubPull {
	p := model.GitHubPull{BodySource: "Fixes the loop.\n\n<!-- notes -->", CanEdit: true}
	p.ID, p.Title = "PR_218", "Fix login redirect loop"
	return p
}

func TestEditPullSendsOnlyWhatChanged(t *testing.T) {
	s, f := worldWith(t, editable())
	title := "  Fix the login redirect loop "
	if err := s.EditPull(t.Context(), pullRef, PullEdit{Title: &title, Was: "Fix login redirect loop"}); err != nil {
		t.Fatal(err)
	}
	body := "Fixes the loop for good."
	if err := s.EditPull(t.Context(), pullRef, PullEdit{Body: &body, Was: "Fixes the loop.\n\n<!-- notes -->"}); err != nil {
		t.Fatal(err)
	}
	if len(f.edits) != 2 {
		t.Fatalf("%+v", f.edits)
	}
	if e := f.edits[0]; e.pull != "PR_218" || e.body != nil || *e.title != "Fix the login redirect loop" {
		t.Fatalf("the title's edit: %+v", e)
	}
	if e := f.edits[1]; e.title != nil || *e.body != body {
		t.Fatalf("the description's edit: %+v", e)
	}
	// An empty description clears it.
	empty := ""
	if err := s.EditPull(t.Context(), pullRef, PullEdit{Body: &empty, Was: "Fixes the loop.\n\n<!-- notes -->"}); err != nil || len(f.edits) != 3 {
		t.Fatal(err, f.edits)
	}
}

// Nothing reaches GitHub unless it still says what the edit began from,
// and lets the user edit it.
func TestEditPullRefusesWithoutSending(t *testing.T) {
	title, body, blank := "New", "New text", "   "
	for _, c := range []struct {
		name string
		edit func(*model.GitHubPull)
		e    PullEdit
		want error
	}{
		{"the title changed since", func(p *model.GitHubPull) { p.Title = "Someone else's" }, PullEdit{Title: &title, Was: "Fix login redirect loop"}, ErrChangedSince},
		{"the description changed since", func(p *model.GitHubPull) { p.BodySource = "Edited by tomas" }, PullEdit{Body: &body, Was: "Fixes the loop.\n\n<!-- notes -->"}, ErrChangedSince},
		{"not the author, no write access", func(p *model.GitHubPull) { p.CanEdit = false }, PullEdit{Body: &body, Was: "Fixes the loop.\n\n<!-- notes -->"}, ErrCantEdit},
		{"both at once", func(*model.GitHubPull) {}, PullEdit{Title: &title, Body: &body}, nil},
		{"neither", func(*model.GitHubPull) {}, PullEdit{}, nil},
		{"an empty title", func(*model.GitHubPull) {}, PullEdit{Title: &blank, Was: "Fix login redirect loop"}, nil},
	} {
		p := editable()
		c.edit(&p)
		s, f := worldWith(t, p)
		err := s.EditPull(t.Context(), pullRef, c.e)
		if err == nil || c.want != nil && !errors.Is(err, c.want) {
			t.Errorf("%s: %v", c.name, err)
		}
		if len(f.edits) != 0 {
			t.Errorf("%s: sent %+v", c.name, f.edits)
		}
	}
}

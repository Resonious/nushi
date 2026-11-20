package github

import (
	"context"
	"errors"
	"strings"

	"github.com/afrase/nushi/internal/model"
)

var (
	// ErrChangedSince is an edit refused because the pull request's title
	// or description isn't what it said when the edit began: saving would
	// overwrite someone else's change unseen.
	ErrChangedSince = errors.New("it changed on GitHub since you opened it, so nothing was saved")
	// ErrCantEdit is GitHub not letting the user edit a pull request
	// (viewerCanUpdate): only its author and people with write access can.
	ErrCantEdit = errors.New("GitHub doesn't let you edit this pull request: only its author and people with write access can")
)

// PullEdit is an edit of a pull request, of its Title or its Body (one,
// the other nil), and Was, what that one said when the edit began (the
// title, or the description's source).
type PullEdit struct {
	Title, Body *string
	Was         string
}

// EditPull sets a pull request's title or description, on the user's ask,
// only while GitHub still has what the edit began from (ErrChangedSince
// else) and lets the user edit it (ErrCantEdit else). The check and the
// write are two requests, so a change between them (a second or so) can
// still be overwritten, as GitHub's own page can.
func (s *Service) EditPull(ctx context.Context, ref model.GitHubRef, e PullEdit) error {
	what := "edit title"
	switch {
	case (e.Title == nil) == (e.Body == nil):
		return errors.New("an edit is of the title or the description")
	case e.Title != nil && strings.TrimSpace(*e.Title) == "":
		return errors.New("a pull request needs a title")
	case e.Body != nil:
		what = "edit description"
	}
	c, err := s.writer(ctx, ref.Host)
	if err != nil {
		return err
	}
	p, err := c.Pull(ctx, ref.Repo, ref.Number)
	if err != nil {
		return err
	}
	if !p.CanEdit {
		return ErrCantEdit
	}
	now := p.Title
	if e.Body != nil {
		now = p.BodySource
	}
	if now != e.Was {
		return ErrChangedSince
	}
	title := e.Title
	if title != nil {
		t := strings.TrimSpace(*title)
		title = &t
	}
	err = c.EditPull(ctx, p.ID, title, e.Body)
	s.wrote(ref.Host, what, err)
	return err
}

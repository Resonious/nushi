package github

import (
	"context"

	"github.com/afrase/nushi/internal/githubapi"
	"github.com/afrase/nushi/internal/model"
)

// Viewed is what the user marked viewed of a pull request's files, as
// GitHub's Files changed keeps it for them: the paths viewed, and those
// viewed before a change since.
func (s *Service) Viewed(ctx context.Context, ref model.GitHubRef, poll bool) (viewed, changed []string, err error) {
	c, err := s.client(ctx, ref.Host)
	if err != nil {
		return nil, nil, err
	}
	if poll {
		ctx = githubapi.Poll(ctx)
	}
	return c.Viewed(ctx, ref.Repo, ref.Number)
}

// SetViewed marks a pull request's file viewed for the user, or not
// (pull is its node id): GitHub's Viewed checkbox.
func (s *Service) SetViewed(ctx context.Context, name, pull, path string, viewed bool) error {
	c, err := s.writer(ctx, name)
	if err != nil {
		return err
	}
	err = c.SetViewed(ctx, pull, path, viewed)
	s.wrote(name, map[bool]string{true: "mark viewed", false: "unmark viewed"}[viewed], err)
	return err
}

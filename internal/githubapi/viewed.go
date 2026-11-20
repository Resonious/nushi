package githubapi

import (
	"context"
	"fmt"
)

const viewedQuery = `query Viewed($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      files(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes { path viewerViewedState } }
    }
  }
}`

// viewedPages is how many pages of a pull request's files Viewed reads:
// 300 files, as many as Compare lists.
const viewedPages = 3

// Viewed is what the viewer marked viewed of a pull request's files
// (GitHub's viewerViewedState): the paths still viewed, and those marked
// before a change since (DISMISSED), which GitHub shows unticked with
// "Changed since last view". The first 300 files.
func (c *Client) Viewed(ctx context.Context, repo string, number int) (viewed, changed []string, err error) {
	owner, name, err := SplitRepo(repo)
	if err != nil {
		return nil, nil, err
	}
	var after *string
	for range viewedPages {
		var data struct {
			Repository *struct {
				PullRequest *struct {
					Files struct {
						PageInfo struct {
							HasNextPage bool   `json:"hasNextPage"`
							EndCursor   string `json:"endCursor"`
						} `json:"pageInfo"`
						Nodes []struct {
							Path  string `json:"path"`
							State string `json:"viewerViewedState"`
						} `json:"nodes"`
					} `json:"files"`
				} `json:"pullRequest"`
			} `json:"repository"`
		}
		vars := map[string]any{"owner": owner, "name": name, "number": number, "after": after}
		if _, err := c.graphql(ctx, viewedQuery, vars, &data); err != nil {
			return nil, nil, err
		}
		if data.Repository == nil || data.Repository.PullRequest == nil {
			return nil, nil, ErrNotFound
		}
		files := data.Repository.PullRequest.Files
		for _, n := range files.Nodes {
			switch n.State {
			case "VIEWED":
				viewed = append(viewed, n.Path)
			case "DISMISSED":
				changed = append(changed, n.Path)
			}
		}
		if !files.PageInfo.HasNextPage {
			break
		}
		after = &files.PageInfo.EndCursor
	}
	return viewed, changed, nil
}

const markViewedMutation = `mutation MarkViewed($pull: ID!, $path: String!) {
  markFileAsViewed(input: {pullRequestId: $pull, path: $path}) { clientMutationId }
}`

const unmarkViewedMutation = `mutation UnmarkViewed($pull: ID!, $path: String!) {
  unmarkFileAsViewed(input: {pullRequestId: $pull, path: $path}) { clientMutationId }
}`

// SetViewed marks a pull request's file viewed for the viewer, or not
// (pull is its node id), as GitHub's Viewed checkbox does.
func (c *Client) SetViewed(ctx context.Context, pull, path string, viewed bool) error {
	if path == "" {
		return fmt.Errorf("which file of %s", pull)
	}
	doc := markViewedMutation
	if !viewed {
		doc = unmarkViewedMutation
	}
	_, err := c.graphql(ctx, doc, map[string]any{"pull": pull, "path": path}, new(any))
	return err
}

package githubapi

import (
	"context"
	"fmt"
	"slices"
	"strings"

	"github.com/afrase/nushi/internal/model"
)

// reactionFields is what a query asks of a comment's, a review's or a
// pull request's reactions: each kind's count and whether the viewer is
// among them. GitHub gives every kind, in its own order.
const reactionFields = `reactionGroups { content viewerHasReacted reactors { totalCount } }`

// Reactions are GitHub's eight, as Nushi names them: GitHub's content
// enum in lower case, in the order its picker shows them.
var Reactions = []string{"thumbs_up", "thumbs_down", "laugh", "hooray", "confused", "heart", "rocket", "eyes"}

// reactionGroup decodes one of reactionFields' groups.
type reactionGroup struct {
	Content          string `json:"content"`
	ViewerHasReacted bool   `json:"viewerHasReacted"`
	Reactors         struct {
		TotalCount int `json:"totalCount"`
	} `json:"reactors"`
}

// reactions are the kinds someone used, in GitHub's order; one GitHub
// adds later that Nushi doesn't know is left out.
func reactions(groups []reactionGroup) []model.GitHubReaction {
	var out []model.GitHubReaction
	for _, g := range groups {
		kind := strings.ToLower(g.Content)
		if g.Reactors.TotalCount == 0 || !knownReaction(kind) {
			continue
		}
		out = append(out, model.GitHubReaction{Content: kind, Count: g.Reactors.TotalCount, Mine: g.ViewerHasReacted})
	}
	return out
}

func knownReaction(kind string) bool { return slices.Contains(Reactions, kind) }

const addReactionMutation = `mutation AddReaction($subject: ID!, $content: ReactionContent!) {
  addReaction(input: {subjectId: $subject, content: $content}) { clientMutationId }
}`

const removeReactionMutation = `mutation RemoveReaction($subject: ID!, $content: ReactionContent!) {
  removeReaction(input: {subjectId: $subject, content: $content}) { clientMutationId }
}`

// React adds the viewer's reaction of kind (one of Reactions) to a
// comment, a review or a pull request (subject is its node id), or takes
// it away.
func (c *Client) React(ctx context.Context, subject, kind string, on bool) error {
	if !knownReaction(kind) {
		return fmt.Errorf("%q isn't one of GitHub's reactions", kind)
	}
	doc := addReactionMutation
	if !on {
		doc = removeReactionMutation
	}
	vars := map[string]any{"subject": subject, "content": strings.ToUpper(kind)}
	_, err := c.graphql(ctx, doc, vars, new(any))
	return err
}

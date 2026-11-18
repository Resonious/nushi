package git

import (
	"context"
	"fmt"
	"slices"
	"strings"

	"github.com/afrase/nushi/internal/model"
)

// Changed lists the folder's changes as Changes does with base (Span.Base),
// by path and status alone: no texts, no line counts, nothing staged, so
// it costs a few git runs whatever the files hold. It runs with no click
// behind it, so with the repository's own filter drivers off (noFilters),
// as Status does. A submodule and a repository inside the folder are left
// out (not looked into). What git ignores isn't listed: a folder holding
// a tracked file isn't ignored, as git (and so the Files pane) sees it.
func Changed(ctx context.Context, folder, base string) ([]model.FileChange, error) {
	from, err := start(ctx, folder, base)
	if err != nil {
		return nil, err
	}
	off, err := noFilters(ctx, folder)
	if err != nil {
		return nil, err
	}
	changes, err := listed(ctx, folder, off, from, "")
	if err != nil {
		return nil, err
	}
	changes = slices.DeleteFunc(changes, func(c model.FileChange) bool { return c.Skipped != "" })
	slices.SortFunc(changes, func(a, b model.FileChange) int { return strings.Compare(a.Path, b.Path) })
	return changes, nil
}

// listed lists the files changed from commit from to commit to (to "" for
// the work tree, with its untracked files; from "" before the first
// commit, every file added), by path and status alone: a submodule and a
// repository inside the folder (git lists its folder) skipped. The diff
// runs with the config settings named in blank set empty (noFilters'
// list, for a run no click asked for); the untracked listing reads no
// file's content, so runs no filter.
func listed(ctx context.Context, folder string, blank []string, from, to string) ([]model.FileChange, error) {
	hasHead := from != ""
	revs := []string{from}
	if to != "" {
		revs = append(revs, to)
	}
	var changes []model.FileChange
	if hasHead {
		out, err := runTo(ctx, folder, blank, nil, append(append([]string{"diff"}, revs...), "--raw", "-z", "-M", "--relative", "--ignore-submodules=dirty", "--no-ext-diff", "--no-textconv")...)
		if err != nil {
			return nil, err
		}
		fields := split(out)
		for i := 0; i+1 < len(fields); i += 2 { // ":<mode> <mode> <sha> <sha> <status>", the path
			head := strings.Fields(fields[i])
			if len(head) < 5 {
				return nil, fmt.Errorf("git diff: can't read %q", fields[i])
			}
			c := model.FileChange{Path: fields[i+1], Status: "modified"}
			switch head[4][0] {
			case 'A':
				c.Status = "added"
			case 'D':
				c.Status = "deleted"
			case 'R': // R<score>, the old path, the new one
				if i+2 < len(fields) {
					c.Status, c.OldPath, c.Path = "renamed", fields[i+1], fields[i+2]
					i++
				}
			}
			if head[0] == ":"+gitlink || head[1] == gitlink {
				c.Skipped = "a submodule"
			}
			changes = append(changes, c)
		}
	}
	if to != "" {
		return changes, nil
	}
	added, err := untracked(ctx, folder, hasHead)
	if err != nil {
		return nil, err
	}
	status := "untracked"
	if !hasHead {
		status = "added" // before the first commit, every file is new
	}
	for _, p := range added {
		c := model.FileChange{Path: p, Status: status}
		if before, ok := strings.CutSuffix(p, "/"); ok { // git lists a repository inside the folder as a folder
			c.Path, c.Skipped = before, "a repository of its own"
		}
		changes = append(changes, c)
	}
	return changes, nil
}

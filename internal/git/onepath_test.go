package git

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/afrase/nushi/internal/model"
	"github.com/afrase/nushi/internal/testcheck"
)

// TestChangesOfOnePath is a file preview's question (Span.Path): only that
// file, with HEAD's text, and an answer that tells "unchanged" apart from
// "nothing to compare".
func TestChangesOfOnePath(t *testing.T) {
	ctx := t.Context()
	repo := t.TempDir()
	sub := filepath.Join(repo, "sub")
	one := func(folder, path string) []model.FileChange {
		t.Helper()
		got, err := Changes(ctx, folder, Span{Path: path})
		if err != nil {
			t.Fatalf("%s: %v", path, err)
		}
		return got
	}

	if _, err := Changes(ctx, repo, Span{Path: "a.txt"}); err == nil {
		t.Error("a folder outside git answered")
	}
	testcheck.Git(t, repo, "init", "-q", "-b", "main")
	testcheck.Write(t, filepath.Join(sub, "a.txt"), "one\n")
	if got := one(sub, "a.txt"); len(got) != 1 || got[0].Status != "added" || got[0].Skipped != "" {
		t.Errorf("before the first commit: %+v", got)
	}

	testcheck.Write(t, filepath.Join(repo, ".gitignore"), "*.log\n")
	testcheck.Write(t, filepath.Join(sub, "b.txt"), "b\n")
	testcheck.Write(t, filepath.Join(sub, "crlf.txt"), "x\r\ny\r\n")
	testcheck.Write(t, filepath.Join(sub, "old.txt"), "keep\n")
	testcheck.Write(t, filepath.Join(sub, "bin"), "a\x00b")
	testcheck.Write(t, filepath.Join(sub, "big.txt"), "x\n")
	testcheck.NoErr(t, os.Symlink("a.txt", filepath.Join(sub, "tracked-link")))
	testcheck.Git(t, repo, "add", ".")
	testcheck.Git(t, repo, "commit", "-q", "-m", "init")

	testcheck.Write(t, filepath.Join(sub, "a.txt"), "one\ntwo\n")
	testcheck.Write(t, filepath.Join(sub, "b.txt"), "b changed\n") // another change, left out
	want := []model.FileChange{{Path: "a.txt", Status: "modified", Old: "one\n", New: "one\ntwo\n", Added: 1}}
	if got := one(sub, "a.txt"); !reflect.DeepEqual(got, want) {
		t.Errorf("modified =\n%+v\nwant\n%+v", got, want)
	}
	if got := one(repo, "sub/a.txt"); len(got) != 1 || got[0].Path != "sub/a.txt" || got[0].Old != "one\n" {
		t.Errorf("from the top: %+v", got)
	}
	if got := one(sub, "old.txt"); len(got) != 0 {
		t.Errorf("unchanged: %+v", got)
	}

	testcheck.Write(t, filepath.Join(sub, "crlf.txt"), "x\r\nz\r\n")
	if got := one(sub, "crlf.txt"); len(got) != 1 || got[0].Old != "x\r\ny\r\n" {
		t.Errorf("CRLF: %+v", got)
	}

	testcheck.Write(t, filepath.Join(sub, "new.txt"), "new\n")
	want = []model.FileChange{{Path: "new.txt", Status: "untracked", New: "new\n", Added: 1}}
	if got := one(sub, "new.txt"); !reflect.DeepEqual(got, want) {
		t.Errorf("untracked: %+v", got)
	}
	testcheck.Write(t, filepath.Join(sub, "x.log"), "ignored\n")
	want = []model.FileChange{{Path: "x.log", Status: "untracked", Skipped: "not tracked"}}
	if got := one(sub, "x.log"); !reflect.DeepEqual(got, want) {
		t.Errorf("ignored: %+v", got)
	}

	testcheck.NoErr(t, os.Symlink("b.txt", filepath.Join(sub, "new-link")))
	if got := one(sub, "new-link"); len(got) != 1 || got[0].Skipped != "a link" {
		t.Errorf("an untracked link: %+v", got)
	}
	if got := one(sub, "tracked-link"); len(got) != 1 || got[0].Skipped != "a link" {
		t.Errorf("a tracked, unchanged link: %+v", got)
	}
	testcheck.NoErr(t, os.Remove(filepath.Join(sub, "tracked-link")))
	testcheck.NoErr(t, os.Symlink("b.txt", filepath.Join(sub, "tracked-link")))
	if got := one(sub, "tracked-link"); len(got) != 1 || got[0].Skipped != "a link" {
		t.Errorf("a changed link: %+v", got)
	}

	testcheck.Write(t, filepath.Join(sub, "bin"), "c\x00d")
	if got := one(sub, "bin"); len(got) != 1 || got[0].Skipped != "binary" {
		t.Errorf("binary: %+v", got)
	}
	testcheck.Write(t, filepath.Join(sub, "big.txt"), strings.Repeat("x\n", maxText))
	if got := one(sub, "big.txt"); len(got) != 1 || got[0].Skipped != "too large" {
		t.Errorf("too large: %+v", got)
	}

	testcheck.NoErr(t, os.Remove(filepath.Join(sub, "b.txt")))
	if got := one(sub, "b.txt"); len(got) != 1 || got[0].Status != "deleted" || got[0].Old != "b\n" {
		t.Errorf("deleted: %+v", got)
	}

	testcheck.Git(t, repo, "mv", "sub/old.txt", "sub/moved.txt")
	testcheck.Write(t, filepath.Join(sub, "moved.txt"), "keep\nmore\n")
	want = []model.FileChange{{Path: "moved.txt", OldPath: "old.txt", Status: "renamed", Old: "keep\n", New: "keep\nmore\n", Added: 1}}
	if got := one(sub, "moved.txt"); !reflect.DeepEqual(got, want) {
		t.Errorf("renamed (no staged part asked) =\n%+v\nwant\n%+v", got, want)
	}

	if got := one(sub, "missing.txt"); len(got) != 1 || got[0].Skipped != "not tracked" {
		t.Errorf("a file that isn't there: %+v", got)
	}
	for _, p := range []string{"../top.txt", "/etc/hosts"} {
		if _, err := Changes(ctx, sub, Span{Path: p}); err == nil {
			t.Errorf("%s: a path outside the folder was read", p)
		}
	}
}

// TestChangesOfOnePathAutocrlf: a file git converts on checkout isn't
// listed as changed, so it reads as unchanged rather than every line.
func TestChangesOfOnePathAutocrlf(t *testing.T) {
	ctx := t.Context()
	repo := t.TempDir()
	testcheck.Git(t, repo, "init", "-q", "-b", "main")
	testcheck.Git(t, repo, "config", "core.autocrlf", "true")
	testcheck.Write(t, filepath.Join(repo, "a.txt"), "x\ny\n")
	testcheck.Git(t, repo, "add", ".")
	testcheck.Git(t, repo, "commit", "-q", "-m", "init")
	testcheck.Write(t, filepath.Join(repo, "a.txt"), "x\r\ny\r\n") // as a checkout writes it
	if got, err := Changes(ctx, repo, Span{Path: "a.txt"}); err != nil || len(got) != 0 {
		t.Errorf("autocrlf: %+v, %v", got, err)
	}
}

// TestChangesOfOnePathOnABranch is a file preview's question with the
// chat's branch base (ADR 0131): one file's change since the branch left
// main, committed or not, as the Changes tab's Branch view counts it.
func TestChangesOfOnePathOnABranch(t *testing.T) {
	ctx := t.Context()
	repo := t.TempDir()
	sub := filepath.Join(repo, "sub")
	testcheck.Git(t, repo, "init", "-q", "-b", "main")
	testcheck.Write(t, filepath.Join(sub, "a.txt"), "one\n")
	testcheck.Write(t, filepath.Join(sub, "b.txt"), "b\n")
	testcheck.Write(t, filepath.Join(sub, "old.txt"), "keep\n")
	testcheck.Write(t, filepath.Join(sub, "same.txt"), "same\n")
	testcheck.Git(t, repo, "add", ".")
	testcheck.Git(t, repo, "commit", "-q", "-m", "init")
	one := func(base, path string) []model.FileChange {
		t.Helper()
		got, err := Changes(ctx, sub, Span{Base: base, Path: path})
		if err != nil {
			t.Fatalf("%s from %q: %v", path, base, err)
		}
		return got
	}
	commit := func(msg string) {
		t.Helper()
		testcheck.Git(t, repo, "add", "-A")
		testcheck.Git(t, repo, "commit", "-q", "-m", msg)
	}

	testcheck.Git(t, repo, "checkout", "-q", "-b", "chat")
	// Changed and committed on the branch: HEAD has it, the base not.
	testcheck.Write(t, filepath.Join(sub, "a.txt"), "one\ntwo\n")
	commit("two")
	want := []model.FileChange{{Path: "a.txt", Status: "modified", Old: "one\n", New: "one\ntwo\n", Added: 1}}
	if got := one("main", "a.txt"); !reflect.DeepEqual(got, want) {
		t.Errorf("committed on the branch =\n%+v\nwant\n%+v", got, want)
	}
	if got := one("", "a.txt"); len(got) != 0 {
		t.Errorf("from the last commit, a committed change is none: %+v", got)
	}
	// Then changed again, uncommitted: both together.
	testcheck.Write(t, filepath.Join(sub, "a.txt"), "one\ntwo\nthree\n")
	want = []model.FileChange{{Path: "a.txt", Status: "modified", Old: "one\n", New: "one\ntwo\nthree\n", Added: 2}}
	if got := one("main", "a.txt"); !reflect.DeepEqual(got, want) {
		t.Errorf("committed, then changed =\n%+v\nwant\n%+v", got, want)
	}

	// Added on the branch, committed or not: new against the base.
	testcheck.Write(t, filepath.Join(sub, "added.txt"), "added\n")
	testcheck.Git(t, repo, "add", "sub/added.txt")
	testcheck.Git(t, repo, "commit", "-q", "-m", "added")
	if got := one("main", "added.txt"); len(got) != 1 || got[0].Status != "added" || got[0].Skipped != "" {
		t.Errorf("added on the branch: %+v", got)
	}
	testcheck.Write(t, filepath.Join(sub, "loose.txt"), "loose\n")
	if got := one("main", "loose.txt"); len(got) != 1 || got[0].Status != "untracked" || got[0].Skipped != "" {
		t.Errorf("untracked on the branch: %+v", got)
	}

	// Renamed on the branch, then changed: against its old path's text.
	testcheck.Git(t, repo, "mv", "sub/old.txt", "sub/moved.txt")
	testcheck.Git(t, repo, "commit", "-q", "-m", "moved")
	testcheck.Write(t, filepath.Join(sub, "moved.txt"), "keep\nmore\n")
	want = []model.FileChange{{Path: "moved.txt", OldPath: "old.txt", Status: "renamed", Old: "keep\n", New: "keep\nmore\n", Added: 1}}
	if got := one("main", "moved.txt"); !reflect.DeepEqual(got, want) {
		t.Errorf("renamed on the branch =\n%+v\nwant\n%+v", got, want)
	}

	// Main moves on, changing a file the branch left alone: counted from
	// where the branch left main, it is unchanged.
	commit("wip")
	testcheck.Git(t, repo, "checkout", "-q", "main")
	testcheck.Write(t, filepath.Join(sub, "same.txt"), "main moved\n")
	commit("main moves")
	testcheck.Git(t, repo, "checkout", "-q", "chat")
	if got := one("main", "same.txt"); len(got) != 0 {
		t.Errorf("changed only on main since: %+v", got)
	}

	// On the base branch itself, the base is HEAD: what's uncommitted.
	testcheck.Git(t, repo, "checkout", "-q", "main")
	testcheck.Write(t, filepath.Join(sub, "b.txt"), "b changed\n")
	want = []model.FileChange{{Path: "b.txt", Status: "modified", Old: "b\n", New: "b changed\n", Added: 1, Removed: 1}}
	if got := one("main", "b.txt"); !reflect.DeepEqual(got, want) {
		t.Errorf("on main =\n%+v\nwant\n%+v", got, want)
	}
	if _, err := Changes(ctx, sub, Span{Base: "gone", Path: "b.txt"}); err == nil {
		t.Error("a base that isn't a branch answered")
	}
}

// TestOnePathFromBeforeAChatsCommits is a file's change marks for a chat
// on main itself, with two commits of its own (ADR 0131's amendment): the
// app names the parent of the oldest commit made since the chat began
// ("<hash>^", from Commits) as the base, so both commits and what's
// uncommitted count, and the user's commit before the chat doesn't.
func TestOnePathFromBeforeAChatsCommits(t *testing.T) {
	ctx := t.Context()
	repo := t.TempDir()
	testcheck.Git(t, repo, "init", "-q", "-b", "main")
	commit := func(text, message string) {
		t.Helper()
		testcheck.Write(t, filepath.Join(repo, "a.txt"), text)
		testcheck.Git(t, repo, "add", "-A")
		testcheck.Git(t, repo, "commit", "-q", "-m", message)
	}
	commit("one\n", "the user's")
	commit("one\ntwo\n", "the chat's first")
	commit("one\ntwo\nthree\n", "the chat's second")
	testcheck.Write(t, filepath.Join(repo, "a.txt"), "one\ntwo\nthree\nfour\n")

	commits, err := Commits(ctx, repo, "", "", 50)
	testcheck.NoErr(t, err)
	if len(commits) != 3 || commits[1].Subject != "the chat's first" {
		t.Fatalf("commits: %+v", commits)
	}
	got, err := Changes(ctx, repo, Span{Base: commits[1].Hash + "^", Path: "a.txt"})
	testcheck.NoErr(t, err)
	want := []model.FileChange{{Path: "a.txt", Status: "modified", Old: "one\n", New: "one\ntwo\nthree\nfour\n", Added: 3}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("from the first one's parent =\n%+v\nwant\n%+v", got, want)
	}
	// From the last commit, as before, only what's uncommitted.
	got, err = Changes(ctx, repo, Span{Path: "a.txt"})
	testcheck.NoErr(t, err)
	if len(got) != 1 || got[0].Old != "one\ntwo\nthree\n" {
		t.Errorf("from the last commit: %+v", got)
	}

	// The chat's first commit the repository's first: it has no parent, so
	// it's refused, and the app asks again of the last commit.
	if _, err := Changes(ctx, repo, Span{Base: commits[2].Hash + "^", Path: "a.txt"}); err == nil {
		t.Error("the first commit's parent answered")
	}
}

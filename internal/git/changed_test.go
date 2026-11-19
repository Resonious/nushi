package git

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/afrase/nushi/internal/model"
	"github.com/afrase/nushi/internal/testcheck"
)

// TestChanged is the Files tree's question: what differs from the base the
// change marks count from, by name, whoever changed it: a branch's commits
// and its uncommitted and untracked files, a rename, but nothing git
// ignores and nothing inside another repository.
func TestChanged(t *testing.T) {
	ctx := t.Context()
	repo := t.TempDir()
	at := func(p string) string { return filepath.Join(repo, p) }
	names := func(base string) []model.FileChange {
		t.Helper()
		got, err := Changed(ctx, repo, base)
		if err != nil {
			t.Fatalf("base %q: %v", base, err)
		}
		return got
	}

	if _, err := Changed(ctx, repo, ""); err == nil {
		t.Error("a folder outside git answered")
	}
	testcheck.Git(t, repo, "init", "-q", "-b", "main")
	testcheck.Write(t, at("a.txt"), "a\n")
	if got := names(""); !reflect.DeepEqual(got, []model.FileChange{{Path: "a.txt", Status: "added"}}) {
		t.Errorf("before the first commit: %+v", got)
	}
	testcheck.Write(t, at(".gitignore"), "*.log\nbuild/\n")
	testcheck.Write(t, at("src/old.go"), "package src\n\nfunc Old() {}\n")
	testcheck.Write(t, at("src/same.go"), "package src\n")
	testcheck.Write(t, at("build/kept.txt"), "kept\n")
	testcheck.Git(t, repo, "add", ".")
	testcheck.Git(t, repo, "add", "-f", "build/kept.txt")
	testcheck.Git(t, repo, "commit", "-q", "-m", "init")

	testcheck.Git(t, repo, "switch", "-q", "-c", "work")
	testcheck.Write(t, at("internal/config/config.go"), "package config\n")
	testcheck.Git(t, repo, "add", ".")
	testcheck.Git(t, repo, "commit", "-q", "-m", "committed on the branch")
	testcheck.Git(t, repo, "mv", "src/old.go", "src/new.go")
	testcheck.Write(t, at("a.txt"), "a changed\n")       // uncommitted
	testcheck.Write(t, at("notes/new.md"), "new\n")      // untracked
	testcheck.Write(t, at("debug.log"), "ignored\n")     // ignored
	testcheck.Write(t, at("build/kept.txt"), "edited\n") // tracked, in an ignored folder
	testcheck.Write(t, at("build/out.bin"), "ignored\n")
	nested := at("vendor/lib")
	testcheck.Write(t, filepath.Join(nested, "x.go"), "package lib\n")
	testcheck.Git(t, nested, "init", "-q", "-b", "main")

	want := []model.FileChange{
		{Path: "a.txt", Status: "modified"},
		{Path: "build/kept.txt", Status: "modified"}, // its folder shows
		{Path: "internal/config/config.go", Status: "added"},
		{Path: "notes/new.md", Status: "untracked"},
		{Path: "src/new.go", Status: "renamed", OldPath: "src/old.go"},
	}
	if got := names("main"); !reflect.DeepEqual(got, want) {
		t.Errorf("against main =\n%+v\nwant\n%+v", got, want)
	}
	// From HEAD the branch's commit is left out.
	if got := names(""); len(got) != 4 || got[2].Path != "notes/new.md" {
		t.Errorf("against HEAD: %+v", got)
	}

	// A chat on main with its own commits: from before the first of them
	// (the marks' "since this chat began").
	testcheck.Git(t, repo, "switch", "-q", "-f", "main")
	testcheck.NoErr(t, os.RemoveAll(nested))
	testcheck.Git(t, repo, "clean", "-qfdx")
	testcheck.Write(t, at("src/same.go"), "package src\n\n// one\n")
	testcheck.Git(t, repo, "commit", "-qam", "the chat's first")
	first := testcheck.Git(t, repo, "rev-parse", "HEAD")
	testcheck.Write(t, at("src/two.go"), "package src\n")
	testcheck.Git(t, repo, "add", ".")
	testcheck.Git(t, repo, "commit", "-qm", "the chat's second")
	want = []model.FileChange{{Path: "src/same.go", Status: "modified"}, {Path: "src/two.go", Status: "added"}}
	if got := names(first + "^"); !reflect.DeepEqual(got, want) {
		t.Errorf("since the chat began =\n%+v\nwant\n%+v", got, want)
	}
	if got := names(""); len(got) != 0 {
		t.Errorf("all committed, against HEAD: %+v", got)
	}

	// A folder inside the repository names its changes relative to itself.
	testcheck.Write(t, at("src/same.go"), "package src\n\n// two\n")
	got, err := Changed(ctx, at("src"), "")
	if err != nil || !reflect.DeepEqual(got, []model.FileChange{{Path: "same.go", Status: "modified"}}) {
		t.Errorf("from src: %+v %v", got, err)
	}
	testcheck.NoErr(t, os.RemoveAll(at("src")))
	if got := names(""); len(got) != 3 || got[0].Status != "deleted" {
		t.Errorf("deleted: %+v", got)
	}
}

// TestChangedRunsNoFilter: the tree's listing runs with no click behind it,
// so a repository's own clean and process filters never run, as for the
// panel's status (TestWorkSinceRunsNoFilter).
func TestChangedRunsNoFilter(t *testing.T) {
	ctx := t.Context()
	repo := t.TempDir()
	testcheck.Git(t, repo, "init", "-q", "-b", "main")
	testcheck.Write(t, filepath.Join(repo, "a.txt"), "one\n")
	testcheck.Write(t, filepath.Join(repo, "b.md"), "one\n")
	testcheck.Git(t, repo, "add", ".")
	testcheck.Git(t, repo, "commit", "-q", "-m", "init")
	marks := t.TempDir()
	clean, process := filepath.Join(marks, "clean-ran"), filepath.Join(marks, "process-ran")
	testcheck.Write(t, filepath.Join(repo, ".gitattributes"), "*.txt filter=evil\n*.md filter=talker\n")
	testcheck.Git(t, repo, "config", "filter.evil.clean", "touch "+clean+"; cat")
	testcheck.Git(t, repo, "config", "filter.talker.process", "touch "+process+"; cat")
	testcheck.Write(t, filepath.Join(repo, "a.txt"), "one\ntwo\n")
	testcheck.Write(t, filepath.Join(repo, "b.md"), "one\ntwo\n")

	got, err := Changed(ctx, repo, "")
	if err != nil || len(got) != 3 { // .gitattributes is untracked
		t.Errorf("%+v, %v", got, err)
	}
	for _, f := range []string{clean, process} {
		if _, err := os.Stat(f); err == nil {
			t.Errorf("a filter ran: %s", filepath.Base(f))
		}
	}
}

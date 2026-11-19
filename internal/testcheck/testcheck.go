// Package testcheck is what Go tests share: failing on an error, JSON,
// writing a file, waiting for a condition, running git without the owner's own
// config, and a package's tests in a home folder of their own. Only tests
// import it.
package testcheck

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// NoErr fails the test on err.
func NoErr(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

// JSON is v as JSON; failing to marshal it fails the test.
func JSON(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	NoErr(t, err)
	return string(b)
}

// Write writes text to the file at path, private (0600), making its
// folders (0700).
func Write(t *testing.T, path, text string) {
	t.Helper()
	NoErr(t, os.MkdirAll(filepath.Dir(path), 0o700))
	NoErr(t, os.WriteFile(path, []byte(text), 0o600))
}

// MainInHome is a package's TestMain for tests that read the home folder
// (an agent's ~/.ante or ~/.claude): they run with HOME an empty temp
// folder, never the user's, which goes once they end. A test that wants
// a home with something in it sets its own. TestMain's return exits
// with m.Run's code.
func MainInHome(m *testing.M) {
	home, err := os.MkdirTemp("", "nushi-test-home-")
	if err != nil {
		panic(err) // no tests run
	}
	defer os.RemoveAll(home) //nolint:errcheck // a temp folder
	_ = os.Setenv("HOME", home)
	m.Run()
}

// Eventually checks cond every 10 ms until it holds, for 5 s at most, and
// says whether it did.
func Eventually(cond func() bool) bool {
	for end := time.Now().Add(5 * time.Second); !cond(); time.Sleep(10 * time.Millisecond) {
		if time.Now().After(end) {
			return cond()
		}
	}
	return true
}

// Git runs git in dir and returns its output, trimmed; it fails the test
// when git does. Neither the global nor the system config is read (no
// hooks, signing or default branch of the owner's), nor their global
// ignore file, which git reads without any config; commits are t's.
func Git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir, "-c", "user.name=t", "-c", "user.email=t@t",
		"-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", "-c", "init.defaultBranch=main",
		"-c", "core.excludesFile=" + os.DevNull}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_NOSYSTEM=1")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("git %v: %v\n%s%s", args, err, out, stderr.Bytes())
	}
	return strings.TrimSpace(string(out))
}

// PutBranch puts the worktree named name of repo on branch, at its commit,
// by writing git's own files as an agent could: a branch of bytes that
// aren't valid UTF-8 can't be made by git on a Mac, whose disks refuse
// them for its ref's file, but git reads it from packed-refs.
func PutBranch(t *testing.T, repo, name, branch string) {
	t.Helper()
	head := Git(t, filepath.Join(repo, ".git", "worktrees", name), "rev-parse", "HEAD")
	f, err := os.OpenFile(filepath.Join(repo, ".git", "packed-refs"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	NoErr(t, err)
	_, err = f.WriteString(head + " refs/heads/" + branch + "\n")
	NoErr(t, errors.Join(err, f.Close()))
	Write(t, filepath.Join(repo, ".git", "worktrees", name, "HEAD"), "ref: refs/heads/"+branch+"\n")
}

package agytrust

import (
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/afrase/nushi/internal/git"
	"github.com/afrase/nushi/internal/testcheck"
)

func TestWhatAgyLoads(t *testing.T) {
	repo := git.RealPath(t.TempDir())
	pkg := filepath.Join(repo, "pkg")
	testcheck.Write(t, filepath.Join(repo, ".git", "HEAD"), "ref: refs/heads/main\n")

	// Code/configs agy loads across customization roots.
	testcheck.Write(t, filepath.Join(repo, ".agents", "hooks.json"), `{"h":{"SessionStart":[{"command":"echo hi"}]}}`)
	testcheck.Write(t, filepath.Join(repo, ".agents", "plugins", "p", "plugin.json"), `{"name":"p"}`)
	testcheck.Write(t, filepath.Join(repo, ".agents", "plugins", "p", "mcp_config.json"), `{"mcpServers":{}}`)
	testcheck.Write(t, filepath.Join(pkg, ".agent", "plugins.json"), `{"entries":[]}`)
	testcheck.Write(t, filepath.Join(pkg, "_agents", "skills.json"), `{"entries":[]}`)

	// Instructions are left out.
	testcheck.Write(t, filepath.Join(repo, "AGENTS.md"), "# rules\n")
	testcheck.Write(t, filepath.Join(repo, "GEMINI.md"), "# rules\n")
	testcheck.Write(t, filepath.Join(repo, ".agents", "rules", "r.md"), "rule\n")
	testcheck.Write(t, filepath.Join(repo, ".agents", "skills", "s", "SKILL.md"), "---\nname: s\n---\n")

	runs, key, err := (Trust{}).Runs(pkg)
	testcheck.NoErr(t, err)
	if !strings.HasPrefix(key, "agy:"+pkg+"#") {
		t.Fatalf("key = %q", key)
	}
	var got []string
	for _, r := range runs {
		got = append(got, filepath.ToSlash(strings.TrimPrefix(r.File, repo)))
	}
	want := []string{
		"/.agents/hooks.json",
		"/.agents/plugins/p/mcp_config.json",
		"/.agents/plugins/p/plugin.json",
		"/pkg/.agent/plugins.json",
		"/pkg/_agents/skills.json",
	}
	if !slices.Equal(got, want) {
		t.Errorf("shown %v\nwant  %v", got, want)
	}
	if trusted, err := (Trust{}).Trusted(pkg, nil); trusted || err != nil {
		t.Errorf("Trusted = %v, %v; want false, nil", trusted, err)
	}
	if gotKey := (Trust{}).Key(pkg); gotKey != key {
		t.Errorf("Key = %q, want %q", gotKey, key)
	}
}

func TestCleanFolderHasNoRuns(t *testing.T) {
	dir := t.TempDir()
	testcheck.Write(t, filepath.Join(dir, "AGENTS.md"), "# rules\n")
	runs, _, err := (Trust{}).Runs(dir)
	testcheck.NoErr(t, err)
	if len(runs) != 0 {
		t.Errorf("runs = %v, want empty", runs)
	}
}

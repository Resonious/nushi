package codex

import (
	"os"
	"slices"
	"testing"

	"github.com/afrase/nushi/internal/model"
)

// The Go agent is this executable's subcommand, in the daemon's folder,
// with the chat's environment and codex's path as the agent reads it.
func TestTheGoAgentsCommand(t *testing.T) {
	env := []string{"PATH=/bin", "HOME=/h"}
	cmd, err := goCommand("/data", "/bin/codex", env)
	self, _ := os.Executable()
	if err != nil || !slices.Equal(cmd.Args, []string{self, "codex-acp"}) || cmd.Dir != "/data" {
		t.Errorf("args %q in %q", cmd.Args, cmd.Dir)
	}
	if want := []string{"PATH=/bin", "HOME=/h", "CODEX_PATH=/bin/codex"}; !slices.Equal(cmd.Env, want) {
		t.Errorf("env %q", cmd.Env)
	}
	if len(env) != 2 {
		t.Errorf("the chat's environment changed: %q", env)
	}
}

// codex-acp runs the user's codex as it is, npm's launcher included,
// which tells Codex how it was installed; only the Go agent runs the
// native binary (Native).
func TestTheAdapterRunsTheLauncher(t *testing.T) {
	if triple, _ := target(); triple == "" {
		t.Skip("Codex has no binary for this platform")
	}
	cli, _ := npmInstall(t, "nested")
	cmd := adapterCommand("/data", model.AgentRun{Node: "/bin/node", Program: "/data/codex-acp.js", CLI: cli, Env: []string{"PATH=/bin"}})
	if want := []string{"PATH=/bin", "CODEX_PATH=" + cli}; !slices.Equal(cmd.Env, want) || cmd.Dir != "/data" {
		t.Errorf("env %q in %q, want %q", cmd.Env, cmd.Dir, want)
	}
}

// Package agy knows what Antigravity CLI (agy 1.5.12, `agy acp`) does
// beyond ACP: how to start it and its quirks, as its Harness; the chats
// feature, which knows nothing of agy, takes that through its interfaces.
// What it does, as seen, is in docs/facts/agy.md.
package agy

import (
	"encoding/json"
	"log/slog"
	"os/exec"
	"path/filepath"
	"strings"

	acp "github.com/afrase/acp-go/unstable"

	"github.com/afrase/nushi/internal/agentproc"
	"github.com/afrase/nushi/internal/model"
)

// Harness is agy as Nushi runs it, for the chats feature's interfaces.
// Nothing here reads agy's files.
type Harness struct{}

// Local is Harness as the daemon runs it, the place for what reads agy's
// files on this machine; nothing does yet. Tests use Harness alone.
type Local struct{ Harness }

// Info is what Harness is. agy connects to a client's stdio MCP servers on
// session/new and asks permission before calling their tools (ClientMCP,
// ADR 0043, 0068), and titles a session itself soon after the first prompt
// (NamesSessions). It has no session/fork or session/delete (no Moves),
// and its plan mode still allows edits (no ReadOnly).
func (Harness) Info() model.HarnessInfo {
	return model.HarnessInfo{
		Name:          "agy",
		Title:         "Antigravity",
		Resume:        "agy --conversation",
		ClientMCP:     true,
		NamesSessions: true,
	}
}

// Start starts the user's agy (r's CLI) as an ACP agent, in dir (the
// daemon's folder) and r's environment (the login shell's, ADR 0048), its
// stderr to log. agy reads its own config and sign-in (~/.gemini); Nushi
// never does. Closing its input exits it cleanly.
func (Harness) Start(dir string, r model.AgentRun, client acp.Client, log *slog.Logger) (*agentproc.Agent, error) {
	cmd := exec.Command(r.CLI, "acp") //nolint:gosec,noctx // lives until Stop or Close, not a context; the agy found on PATH
	cmd.Dir, cmd.Env = dir, r.Env
	return agentproc.Start(cmd, client, log)
}

// CLI is agy's program.
const CLI = "agy"

// Tested are the agy versions Nushi was run with.
var Tested = []string{"1.5.12"}

// ConfigDir is agy's global customization folder (skills, plugins, hooks,
// mcp_config.json), for a user whose home folder is home.
func ConfigDir(home string) string {
	return filepath.Join(home, ".gemini", "config")
}

// Other says field is the free-text answer agy puts after a question with
// choices: `<id>_other`, "Other".
func (Harness) Other(field, before model.Field) bool {
	return len(field.Options) == 0 && field.ID == before.ID+"_other"
}

// ToolCall drops the "Run " agy puts before an MCP tool's title (such as
// "Run mcp_nushi_show"), so Nushi's tool rows and preview actions match it
// cleanly.
func (Harness) ToolCall(it *model.Item, _ map[string]any, _ json.RawMessage) (ownText bool) {
	if strings.HasPrefix(it.Title, "Run mcp_") {
		it.Title = strings.TrimPrefix(it.Title, "Run ")
	}
	return false
}

package codex

import (
	"os/exec"

	"github.com/afrase/nushi/internal/agentproc"
)

// AgentCommand is the subcommand nushid runs Codex's Go agent under
// (codexacp.Main): `nushid codex-acp`.
const AgentCommand = "codex-acp"

// goCommand is Nushi's Go agent for Codex: this executable's
// AgentCommand, in dir (the daemon's folder) and env, running cli, the
// user's Codex, as its native binary with the launcher's variables
// (Native). It needs no Node and nothing set up. The agent reads codex's
// path from CODEX_PATH, as codex-acp does.
func goCommand(dir, cli string, env []string) (*exec.Cmd, error) {
	return agentproc.SelfCommand(AgentCommand, dir, nativeEnv(cli, env))
}

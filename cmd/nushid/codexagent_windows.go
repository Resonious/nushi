package main

import (
	"os"
	"slices"

	"github.com/afrase/codex-acp-go/appserver"
	"github.com/afrase/codex-acp-go/codexacp"

	"github.com/afrase/nushi/internal/batchfile"
)

// runCodexAgent runs Codex's Go agent (codexacp.Main), the codex-acp
// subcommand, with each app-server started through spawnCodex: a codex
// that is still npm's batch file must not run through cmd.exe.
func runCodexAgent() error { return codexacp.Main(codexacp.Config{Spawn: spawnCodex}) }

// spawnCodex starts codex app-server as appserver.Exec does, guarded
// against cmd.exe as batchfile.Guard guards what the daemon starts: a
// codex that is an npm shim (no native binary found, codex.Native) runs
// as node and its script, and nothing runs from the current folder by a
// bare name. The app-server is the agent's plain child, so the daemon's kill of
// the agent's process tree takes it too.
func spawnCodex(s appserver.Spec) (appserver.Proc, error) {
	if s.Env != nil {
		s.Env = batchfile.Environ(s.Env)
	}
	env := s.Env
	if env == nil {
		env = os.Environ()
	}
	path, args, progEnv, err := batchfile.Command(s.Path, s.Args, env)
	if err != nil {
		return appserver.Proc{}, err
	}
	s.Path, s.Args = path, args
	if s.Env != nil || !slices.Equal(progEnv, env) { // a shim's NODE_PATH
		s.Env = progEnv
	}
	return appserver.Exec(s)
}

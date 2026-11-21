package main

import (
	"context"
	"path/filepath"

	"github.com/afrase/claude-acp-go/claudeacp"
	"github.com/afrase/claude-acp-go/claudeagent"

	"github.com/afrase/nushi/internal/batchfile"
	"github.com/afrase/nushi/internal/shellenv"
)

// runClaudeAgent runs Claude's Go agent, the claude-acp subcommand, with
// each claude started through spawnClaude: claude installed by npm is a
// batch file.
func runClaudeAgent() error { return claudeacp.Main(claudeacp.Config{Spawn: spawnClaude}) }

// spawnClaude starts claude as claudeagent.Exec does, guarded against
// cmd.exe (batchfile.Command): npm's claude.cmd runs as node and its
// script, so neither a project's node.exe nor the arguments' quotes and
// `%` (an MCP config's JSON, a settings path) reach cmd.exe.
func spawnClaude(ctx context.Context, s claudeagent.Spec) (*claudeagent.Proc, error) {
	if !filepath.IsAbs(s.Path) {
		if p := shellenv.LookPath(s.Path, s.Env); p != "" {
			s.Path = p
		}
	}
	s.Env = batchfile.Environ(s.Env)
	path, args, env, err := batchfile.Command(s.Path, s.Args, s.Env)
	if err != nil {
		return nil, err
	}
	s.Path, s.Args, s.Env = path, args, env
	return claudeagent.Exec(ctx, s)
}

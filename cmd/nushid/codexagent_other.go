//go:build !windows

package main

import "github.com/afrase/codex-acp-go/codexacp"

// runCodexAgent runs Codex's Go agent (codexacp.Main), the codex-acp
// subcommand, with the library's own appserver.Exec: the app-server stays
// in the agent's process group, so the daemon's kill of that group
// (acp-go's Close) takes it and what Codex started in it too, and it
// stops by itself once its stdin closes.
func runCodexAgent() error { return codexacp.Main(codexacp.Config{}) }

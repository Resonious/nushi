//go:build !windows

package main

import "github.com/afrase/claude-acp-go/claudeacp"

// runClaudeAgent runs Claude's Go agent (claudeacp.Main), the claude-acp
// subcommand.
func runClaudeAgent() error { return claudeacp.Main(claudeacp.Config{}) }

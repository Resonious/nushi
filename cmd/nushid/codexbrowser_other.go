//go:build !linux && !windows

package main

import "context"

// openSignInPage is nil: the library opens Codex's sign-in page itself
// (macOS's open hands it to LaunchServices, outside the agent's group).
var openSignInPage func(ctx context.Context, page string) error

package main

import (
	"context"
	"os/exec"
	"syscall"
)

// xdgOpen is the program that opens a page in the user's browser.
var xdgOpen = "xdg-open"

// openSignInPage opens Codex's sign-in page (a web page the library has
// checked) with xdg-open in a session of its own: a browser it starts, when
// none runs yet, would otherwise join the sign-in agent's process group and
// die with it as the daemon stops that agent, right after the login.
func openSignInPage(ctx context.Context, page string) error {
	cmd := exec.CommandContext(context.WithoutCancel(ctx), xdgOpen, page) //nolint:gosec // page is a checked web URL, an argument, no shell
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() { _ = cmd.Wait() }()
	return nil
}

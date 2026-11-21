package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"

	"golang.org/x/sys/unix"

	"github.com/afrase/nushi/internal/testcheck"
)

// The sign-in page's opener runs in a session of its own, so the browser
// it starts outlives the kill of the sign-in agent's process group.
func TestSignInPageOpensOutsideTheAgentsGroup(t *testing.T) {
	dir := t.TempDir()
	pidFile := filepath.Join(dir, "pid")
	opener := filepath.Join(dir, "xdg-open")
	testcheck.Write(t, opener, "#!/bin/sh\necho $$ > "+pidFile+".tmp\nmv "+pidFile+".tmp "+pidFile+"\nexec sleep 100\n")
	testcheck.NoErr(t, os.Chmod(opener, 0o700))
	old := xdgOpen
	xdgOpen = opener
	t.Cleanup(func() { xdgOpen = old })

	testcheck.NoErr(t, openSignInPage(t.Context(), "https://example.com/login"))
	var pid int
	if !testcheck.Eventually(func() bool {
		b, err := os.ReadFile(pidFile)
		if err != nil {
			return false
		}
		pid, err = strconv.Atoi(strings.TrimSpace(string(b)))
		return err == nil
	}) {
		t.Fatal("the opener didn't run")
	}
	t.Cleanup(func() { _ = syscall.Kill(pid, syscall.SIGKILL) })
	sid, err := unix.Getsid(pid)
	testcheck.NoErr(t, err)
	group, err := syscall.Getpgid(pid)
	testcheck.NoErr(t, err)
	if sid != pid || group != pid || group == syscall.Getpgrp() {
		t.Errorf("opener %d: session %d, group %d, ours %d", pid, sid, group, syscall.Getpgrp())
	}
}

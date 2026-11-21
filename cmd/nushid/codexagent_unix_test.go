//go:build unix

package main

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/afrase/codex-acp-go/appserver"

	"github.com/afrase/nushi/internal/testcheck"
)

// spawnHelper is the variable that makes TestSpawnCodexHelper the agent:
// the app-server's program it names is started as runCodexAgent has it
// started on Unix (codexacp.Main's default, appserver.Exec), its pid
// written to stdout, and the helper waits to be killed.
const spawnHelper = "NUSHID_TEST_SPAWN_CODEX"

// TestSpawnCodexHelper is the agent of TestAppServerDiesWithTheAgentsGroup,
// in a process of its own; it does nothing in a plain run.
func TestSpawnCodexHelper(t *testing.T) {
	program := os.Getenv(spawnHelper)
	if program == "" {
		return
	}
	p, err := appserver.Exec(appserver.Spec{Path: program, Args: []string{"app-server"}})
	testcheck.NoErr(t, err)
	line, err := bufio.NewReader(p.Out).ReadString('\n')
	testcheck.NoErr(t, err)
	_, _ = os.Stdout.WriteString(line)
	time.Sleep(time.Hour) // until the test kills its group
}

// The daemon stops an agent by killing its process group (acp-go's
// Close); the app-server the agent started goes with it, as codex-acp's
// child does, rather than living on beside nobody.
func TestAppServerDiesWithTheAgentsGroup(t *testing.T) {
	program := filepath.Join(t.TempDir(), "codex")
	testcheck.Write(t, program, "#!/bin/sh\necho $$\nexec sleep 100\n")
	testcheck.NoErr(t, os.Chmod(program, 0o700))
	self, err := os.Executable()
	testcheck.NoErr(t, err)
	agent := exec.CommandContext(t.Context(), self, "-test.run=^TestSpawnCodexHelper$")
	agent.Env = append(os.Environ(), spawnHelper+"="+program)
	agent.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} // as acp-go starts an agent
	out, err := agent.StdoutPipe()
	testcheck.NoErr(t, err)
	testcheck.NoErr(t, agent.Start())
	t.Cleanup(func() { _ = syscall.Kill(-agent.Process.Pid, syscall.SIGKILL); _ = agent.Wait() })
	line, err := bufio.NewReader(out).ReadString('\n')
	testcheck.NoErr(t, err)
	server, err := strconv.Atoi(strings.TrimSpace(line))
	testcheck.NoErr(t, err)
	t.Cleanup(func() { _ = syscall.Kill(server, syscall.SIGKILL) })

	testcheck.NoErr(t, syscall.Kill(-agent.Process.Pid, syscall.SIGKILL))
	_ = agent.Wait()
	if !testcheck.Eventually(func() bool { return syscall.Kill(server, 0) != nil }) {
		t.Error("the app-server outlived the agent's group")
	}
}

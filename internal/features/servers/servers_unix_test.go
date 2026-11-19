//go:build unix

package servers

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"
	"time"

	"github.com/afrase/nushi/internal/model"
	"github.com/afrase/nushi/internal/proctree"
	"github.com/afrase/nushi/internal/testcheck"
)

// gone says whether pid has ended (or is a zombie no one waits for).
func gone(pid int) bool {
	if syscall.Kill(pid, 0) != nil {
		return true
	}
	p, err := proctree.Tree{}.Get(pid)
	return err != nil || p.Pid == 0
}

// A child that setsid out of the server's terminal ends with it.
func TestStopEndsAChildThatLeftTheTerminal(t *testing.T) {
	pidFile := filepath.Join(t.TempDir(), "child")
	s, _, _ := setup(t, entry("web", freePort(t), "-child", pidFile))
	_, err := s.Start(t.Context(), "c", Pick{Name: "web"})
	testcheck.NoErr(t, err)
	r := row(t, s, "web", Running)
	b, err := os.ReadFile(pidFile)
	testcheck.NoErr(t, err)
	child, _ := strconv.Atoi(string(b))
	defer syscall.Kill(child, syscall.SIGKILL) //nolint:errcheck // in case the test fails
	if gone(child) {
		t.Fatal("the child didn't start")
	}
	testcheck.NoErr(t, s.Stop("c", r.ServerID))
	if !testcheck.Eventually(func() bool { return gone(child) }) {
		t.Error("the child that left the terminal still runs")
	}
}

// What a crashed daemon's record names, still the same process, is
// stopped; a pid now another process's isn't.
func TestSweepStopsWhatACrashLeft(t *testing.T) {
	cmd := exec.Command(fakeServer, "-sleep")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	testcheck.NoErr(t, cmd.Start())
	done := make(chan struct{})
	go func() { _ = cmd.Wait(); close(done) }()
	defer cmd.Process.Kill() //nolint:errcheck // in case the test fails
	p, err := proctree.Tree{}.Get(cmd.Process.Pid)
	testcheck.NoErr(t, err)
	other, err := proctree.Tree{}.Get(os.Getpid())
	testcheck.NoErr(t, err)
	at := func(p model.Process, d time.Duration) recordedProc {
		return recordedProc{Pid: p.Pid, Pgid: p.Pgid, Started: p.Started.Add(d)}
	}
	path := filepath.Join(t.TempDir(), "servers.json")
	b, _ := json.Marshal(map[string]recorded{"a": {Procs: []recordedProc{at(p, 0), at(other, time.Second)}}})
	testcheck.Write(t, path, string(b))
	Sweep(path, proctree.Tree{})
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Error("the leftover still runs")
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the record is still there: %v", err)
	}
}

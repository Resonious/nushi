package main

import (
	"errors"
	"fmt"
	"log/slog"
	"os"

	"golang.org/x/sys/windows"
)

// stopEventSignal is what the stop event sends on the daemon's stop
// channel: the app asked it to stop, as SIGTERM does on Unix.
type stopEventSignal struct{}

func (stopEventSignal) String() string { return "the app's stop event" }
func (stopEventSignal) Signal()        {}

// stopEventName is the name of the stop event of the daemon whose process
// is pid, in the session's own namespace: the app makes the same from the
// pid Ping gives it (app_install_windows.dart).
func stopEventName(pid int) string { return fmt.Sprintf(`Local\nushid-%d-stop`, pid) }

// watchStopEvent makes the daemon's stop event and sends on stop once
// it's set (ADR 0134). Windows has no SIGTERM to send a process with no
// console window, and a Windows Unix socket doesn't name the process at
// its other end, so the app stops its daemon by setting this event, named
// by the pid the daemon's Ping says. Only the user's own processes can set
// it (the event's default DACL), which could end the daemon anyway. One
// that already exists isn't the daemon's: another process made it first,
// and the daemon doesn't stop by it.
func watchStopEvent(stop chan<- os.Signal) {
	name, err := windows.UTF16PtrFromString(stopEventName(os.Getpid()))
	if err != nil {
		return
	}
	event, err := windows.CreateEvent(nil, 1, 0, name)
	if errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		_ = windows.CloseHandle(event)
		slog.Warn("the stop event was another process's, so the app can't stop the daemon")
		return
	}
	if err != nil {
		slog.Warn("no stop event, so the app can't stop the daemon", "err", err)
		return
	}
	go func() {
		// The handle is kept for the process's life: the name stays the
		// daemon's while it runs.
		if s, err := windows.WaitForSingleObject(event, windows.INFINITE); err != nil || s != windows.WAIT_OBJECT_0 {
			return
		}
		select {
		case stop <- stopEventSignal{}:
		default: // a signal came first
		}
	}()
}

package main

import (
	"os"
	"testing"
	"time"

	"golang.org/x/sys/windows"
)

// The app's stop event, set by its name as the app sets it, stops the
// daemon; one another process made first is left alone.
func TestStopEventStopsTheDaemon(t *testing.T) {
	stop := make(chan os.Signal, 1)
	watchStopEvent(stop)
	name, err := windows.UTF16PtrFromString(stopEventName(os.Getpid()))
	if err != nil {
		t.Fatal(err)
	}
	event, err := windows.OpenEvent(windows.EVENT_MODIFY_STATE, false, name)
	if err != nil {
		t.Fatal(err)
	}
	defer windows.CloseHandle(event) //nolint:errcheck // the test's own handle
	if err := windows.SetEvent(event); err != nil {
		t.Fatal(err)
	}
	select {
	case sig := <-stop:
		if signalName(sig) != "the app's stop event" {
			t.Errorf("stopped by %q", signalName(sig))
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the daemon didn't stop")
	}

	// The process's event exists now, so a second watch finds it made.
	again := make(chan os.Signal, 1)
	watchStopEvent(again)
	if err := windows.SetEvent(event); err != nil {
		t.Fatal(err)
	}
	select {
	case <-again:
		t.Error("an event the daemon didn't make stopped it")
	case <-time.After(100 * time.Millisecond):
	}
}

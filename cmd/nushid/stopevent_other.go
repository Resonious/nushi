//go:build !windows

package main

import "os"

// watchStopEvent does nothing: on Unix the app stops its daemon with
// SIGTERM, by the pid its socket's other end has.
func watchStopEvent(chan<- os.Signal) {}

// Package restart stops the daemon for a newer build once nothing would
// be lost (ADR 0056): the app asks while it bundles a newer daemon than
// the one running, again every few seconds, and starts the new one once
// this one has gone.
package restart

import (
	"log/slog"
	"sync"
	"time"

	"github.com/afrase/nushi/internal/model"
)

// Chats are the chats (internal/features/chats).
type Chats interface {
	// Rest says whether every chat is quiet, and if so takes no prompts
	// from then on; otherwise it names a chat that isn't.
	Rest() (ok bool, holding string)
	// Unrest takes prompts again after Rest, when the restart backs out.
	Unrest()
	// Holding says what keeps each chat that isn't quiet busy, changing
	// nothing.
	Holding() []model.Hold
}

// Runners are what runs beside the chats, as Together: the terminals
// (internal/features/terminals) and the dev servers
// (internal/features/servers, ADR 0098), which end with the daemon, and an
// update's install (internal/features/updates, ADR 0109), which doesn't
// but is waited out.
type Runners interface {
	Busy() bool            // one runs something
	Running() []model.Hold // those that run something
}

// Together is several Runners as one: busy while any is.
type Together []Runners

// Busy says whether any of them is busy.
func (t Together) Busy() bool {
	for _, x := range t {
		if x.Busy() {
			return true
		}
	}
	return false
}

// Running is what runs in each of them, in turn.
func (t Together) Running() []model.Hold {
	var out []model.Hold
	for _, x := range t {
		out = append(out, x.Running()...)
	}
	return out
}

// Service waits, once asked, for nothing to run, and then says the daemon
// is to stop (Due).
type Service struct {
	chats   Chats
	runners Runners

	// Every is how often it looks again while it waits; Lease how long an
	// ask holds unless asked again: an app that quit can't start the new
	// daemon, so this one keeps running.
	Every, Lease time.Duration
	// Looked, when set, is called after each look that found something
	// running, once Every has passed: with true while the ask holds,
	// false once it has lapsed and the waiting stops. A test counts them.
	Looked func(waiting bool)

	mu      sync.Mutex
	until   time.Time // when the last ask lapses
	waiting bool
	due     chan struct{}
}

// New returns the service, not asked yet.
func New(chats Chats, runners Runners) *Service {
	return &Service{chats: chats, runners: runners, Every: time.Second, Lease: 15 * time.Second, due: make(chan struct{})}
}

// WhenIdle asks for the restart, or again: at once if nothing would be
// lost, else once nothing would. It says what the restart waits for now,
// for the app's bar.
func (s *Service) WhenIdle() []model.Hold {
	s.mu.Lock()
	s.until = time.Now().Add(s.Lease)
	if !s.waiting {
		s.waiting = true
		go s.wait()
	}
	s.mu.Unlock()
	return append(s.chats.Holding(), s.runners.Running()...)
}

// Due is closed when the daemon is to stop for its restart: the chats
// take no prompts any more.
func (s *Service) Due() <-chan struct{} { return s.due }

func (s *Service) wait() {
	tick := time.NewTicker(s.Every)
	defer tick.Stop()
	last := "-"
	for {
		holding := "" // a chat's id, or "" for a terminal
		if !s.runners.Busy() {
			var ok bool
			if ok, holding = s.chats.Rest(); ok && !s.runners.Busy() {
				slog.Info("restarting into the newer daemon: nothing runs")
				close(s.due)
				return
			} else if ok { // a command started while the chats came to rest
				s.chats.Unrest()
			}
		}
		if holding != last {
			if holding == "" {
				slog.Info("restart waits: a terminal runs a command")
			} else {
				slog.Info("restart waits: a chat runs or waits", "chat", holding)
			}
			last = holding
		}
		<-tick.C
		s.mu.Lock()
		lapsed := time.Now().After(s.until)
		s.waiting = !lapsed
		s.mu.Unlock()
		if s.Looked != nil {
			s.Looked(!lapsed)
		}
		if lapsed {
			slog.Info("restart no longer asked: the app stopped asking")
			return
		}
	}
}

package relay

import (
	"context"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"time"
)

// NewServer is the relay's HTTP server: New's handler, with timeouts and
// caps on plain connections (not WebSockets, or not yet), so idle or slow
// ones can't pile up or crowd out the daemons and phones. A new connection
// gets FirstWait for its first request's headers, a later request 5 s, and
// it waits HTTPIdle between requests. Per address, at most PlainPerIP are
// open and new ones come at the WebSockets' rate, and per IPv6 /48 at most
// PlainPerNet; the address is the TCP peer's from the accept, or from a
// trusted proxy (IPHeader, TrustedProxies) the header's once a request
// has come. New connections that haven't sent a request yet have
// a budget of their own, a tenth of Total: when it's spent, the oldest of
// them makes way for a new one. When Total are open, the oldest of them
// does, else the one idle longest, else one in the middle of an answer
// (shedAnswer).
func NewServer(lim Limits) *http.Server {
	srv, _ := newServer(lim)
	return srv
}

func newServer(lim Limits) (*http.Server, *server) {
	s := New(lim).(*server) //nolint:forcetypeassert // New makes one
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.served(r) {
			w.Header().Set("Connection", "close")
			http.Error(w, "busy", http.StatusServiceUnavailable)
			return
		}
		s.ServeHTTP(w, r)
	})
	return &http.Server{Handler: h, ConnState: s.connState,
		ConnContext:       func(ctx context.Context, c net.Conn) context.Context { return context.WithValue(ctx, connKey{}, c) },
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, IdleTimeout: lim.HTTPIdle, MaxHeaderBytes: 8 << 10,
		ErrorLog: log.New(io.Discard, "", 0)}, s // its messages name clients' addresses
}

type connKey struct{}

// plain counts the plain connections.
type plain struct {
	conns map[net.Conn]*plainConn
	by    sources        // per address: conns open and the rate
	nets  map[string]int // conns open per /48 (netKey)
	fresh int            // conns without a request yet
}

type plainConn struct {
	key   string    // its address's, once known
	net   string    // its /48's, with key
	idle  bool      // waiting for a request: new, or between two
	since time.Time // when it was accepted, or began to wait
	// answer is when it began answering a request that isn't for a
	// WebSocket (a file, mostly), zero when it isn't.
	answer time.Time
	fresh  *time.Timer // until its first request: closes it after FirstWait
}

// connState counts a connection from its accept until it closes or becomes
// a WebSocket (which join counts).
func (s *server) connState(c net.Conn, st http.ConnState) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	pc := s.plain.conns[c]
	switch st {
	case http.StateNew:
		key, nkey := "", ""
		if addr := c.RemoteAddr().String(); !s.proxied(addr) {
			key, nkey = keyOf(addr, 64), keyOf(addr, 48)
			if !s.admitPlain(key, nkey, now, true) {
				_ = c.Close()
				return
			}
		}
		if s.plain.fresh >= max(1, s.lim.Total/10) {
			s.shed(true) // the oldest without a request makes way
		}
		if len(s.plain.conns) >= s.lim.Total && !s.makeRoom() {
			s.leavePlain(key, nkey, now)
			_ = c.Close()
			return
		}
		pc := &plainConn{key: key, net: nkey, idle: true, since: now}
		pc.fresh = time.AfterFunc(s.lim.FirstWait, func() { s.late(c, pc) })
		s.plain.conns[c] = pc
		s.plain.fresh++
	case http.StateActive:
		if pc != nil {
			pc.idle = false
		}
	case http.StateIdle:
		if pc != nil {
			pc.idle, pc.since, pc.answer = true, now, time.Time{}
		}
	case http.StateHijacked, http.StateClosed:
		if pc != nil {
			s.drop(c)
		}
	}
}

// drop uncounts plain connection c. Called with s.mu.
func (s *server) drop(c net.Conn) {
	pc := s.plain.conns[c]
	delete(s.plain.conns, c)
	s.unFresh(pc)
	s.leavePlain(pc.key, pc.net, time.Now())
}

// admitPlain counts a plain connection under its address's key and its
// /48's, or says it may not be: the address opens them too fast (isNew:
// sources.admit) or holds PlainPerIP, or the /48 holds PlainPerNet.
// Called with s.mu.
func (s *server) admitPlain(key, nkey string, now time.Time, isNew bool) bool {
	if s.plain.nets[nkey] >= s.lim.PlainPerNet || s.plain.by.admit(key, now, s.lim.PlainPerIP, isNew) != 0 {
		return false
	}
	s.plain.nets[nkey]++
	return true
}

// leavePlain uncounts what admitPlain counted; an empty key is a
// connection not counted yet. Called with s.mu.
func (s *server) leavePlain(key, nkey string, now time.Time) {
	if key == "" {
		return
	}
	s.plain.by.leave(key, now)
	if s.plain.nets[nkey]--; s.plain.nets[nkey] <= 0 {
		delete(s.plain.nets, nkey)
	}
}

func (s *server) unFresh(pc *plainConn) {
	if pc.fresh != nil {
		pc.fresh.Stop()
		pc.fresh = nil
		s.plain.fresh--
	}
}

// late closes c if it hasn't sent a request within FirstWait.
func (s *server) late(c net.Conn, pc *plainConn) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.plain.conns[c] == pc && pc.fresh != nil {
		s.drop(c)
		_ = c.Close()
	}
}

// served counts r's connection as one that has sent a request and, behind
// a proxy, under the header's address; it says no when that address (or
// its /48) is over its caps.
func (s *server) served(r *http.Request) bool {
	c, _ := r.Context().Value(connKey{}).(net.Conn)
	s.mu.Lock()
	defer s.mu.Unlock()
	pc := s.plain.conns[c]
	if pc == nil {
		return true
	}
	s.unFresh(pc)
	if pc.answer.IsZero() && !strings.HasPrefix(r.URL.Path, "/v1/") {
		pc.answer = time.Now() // over HTTP/2, its first stream's
	}
	key := s.sourceKey(r)
	if pc.key == key {
		return true
	}
	// A connection that has carried a request already is a proxy's,
	// pooled, now carrying another client's: not a new one of this
	// client's, so it costs none of its rate.
	now, nkey := time.Now(), s.netKey(r)
	if !s.admitPlain(key, nkey, now, pc.key == "") {
		return false
	}
	s.leavePlain(pc.key, pc.net, now)
	pc.key, pc.net = key, nkey
	return true
}

// makeRoom closes one plain connection for a new one when Total are
// open: the oldest fresh one, else the one idle longest, else one in the
// middle of an answer. It says whether there was one. Called with s.mu.
func (s *server) makeRoom() bool {
	return s.shed(true) || s.shed(false) || s.shedAnswer()
}

// shed closes the oldest plain connection without a request yet (fresh),
// idle or still sending its headers, or else the one idle longest; it says
// whether there was one. Called with s.mu.
func (s *server) shed(fresh bool) bool {
	var oldest net.Conn
	for c, pc := range s.plain.conns {
		if (fresh && pc.fresh != nil || !fresh && pc.idle) && (oldest == nil || pc.since.Before(s.plain.conns[oldest].since)) {
			oldest = c
		}
	}
	if oldest == nil {
		return false
	}
	s.drop(oldest)
	_ = oldest.Close()
	return true
}

// shedAnswer closes a plain connection in the middle of an answer, for when
// Total are open and none is fresh or idle: a client that asks for a big
// file and doesn't read it holds its connection until the write deadline,
// and a few networks of them could hold them all. Of those answering, it
// takes one from the /48 holding the most plain connections, and of those
// the one answering longest: a phone loading the app on a poor link, with
// a handful open, goes only once every network holds no more than it
// does. A WebSocket's request is never one: its connection is hijacked as
// it upgrades, and no longer plain. It says whether there was one. Called
// with s.mu.
func (s *server) shedAnswer() bool {
	var victim net.Conn
	var most int
	for c, pc := range s.plain.conns {
		if pc.answer.IsZero() {
			continue
		}
		if n := s.plain.nets[pc.net]; victim == nil || n > most || n == most && pc.answer.Before(s.plain.conns[victim].answer) {
			victim, most = c, n
		}
	}
	if victim == nil {
		return false
	}
	s.drop(victim)
	_ = victim.Close()
	return true
}

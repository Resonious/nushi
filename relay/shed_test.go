package relay

import (
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"slices"
	"sync"
	"testing"
	"testing/fstest"
	"time"

	"github.com/afrase/nushi/internal/testcheck"
)

// stallAfter is how much a stalling connection sends before its writes
// block: a client's receive window and the kernel's buffers, which a client
// that never reads fills. Every answer but a big file's fits.
const stallAfter = 64 << 10

// stallListener's connections stand in for clients that never read: once
// one has sent stallAfter its writes block until it is closed, and it says
// so on stalled. Kernel buffers would do the same, only after an amount
// that differs by system and load.
type stallListener struct {
	net.Listener
	stalled chan struct{}
}

func (l *stallListener) Accept() (net.Conn, error) {
	c, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	return &stallConn{Conn: c, stalled: l.stalled, closed: make(chan struct{})}, nil
}

type stallConn struct {
	net.Conn
	stalled chan<- struct{}
	sent    int  // by the connection's one writer
	told    bool // likewise
	once    sync.Once
	closed  chan struct{}
}

func (c *stallConn) Write(b []byte) (int, error) {
	if c.sent+len(b) <= stallAfter {
		c.sent += len(b)
		return c.Conn.Write(b)
	}
	if !c.told {
		c.told = true
		c.stalled <- struct{}{}
	}
	<-c.closed
	return 0, net.ErrClosed
}

func (c *stallConn) Close() error {
	c.once.Do(func() { close(c.closed) })
	return c.Conn.Close()
}

// The security review of 2026-11-18 (finding 1): clients that ask for a
// big file and never read it held every plain connection, their answers
// running until the write deadline, minutes for the app's biggest files,
// and nothing shed them; every new connection was closed at its accept, a
// WebSocket's upgrade included. Now one /48 holds PlainPerNet of them at
// most, and when Total are open an answer from the most crowded /48 makes
// way: an unrelated client is answered and a daemon and a phone meet.
//
// The review's version opened 1,000 sockets, read a byte of each and slept
// 3 s; this one fills a Total of 40, its clients' stalls signalled by the
// listener rather than left to kernel buffers, and no wait times out.
func TestSlowReadersDontFillThePlainPool(t *testing.T) {
	big := make([]byte, 1<<20)
	_, _ = rand.Read(big)
	site, err := NewSite(fstest.MapFS{"index.html": {Data: []byte("x")}, "big.bin": {Data: big}}, "http://127.0.0.1")
	if err != nil {
		t.Fatal(err)
	}
	lim := Defaults
	lim.Site = site
	lim.IPHeader = "X-Test-IP" // loopback is the trusted proxy, standing in for direct IPv6 peers
	lim.Total, lim.PlainPerIP, lim.PlainPerNet = 40, 8, 16
	lim.HTTPIdle, lim.FirstWait = time.Hour, time.Hour // only the caps close one here
	srv, s := newServer(lim)
	inner, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ln := &stallListener{Listener: inner, stalled: make(chan struct{}, 2*lim.Total)}
	go func() { _ = srv.Serve(ln) }()
	t.Cleanup(func() { _ = srv.Close() }) // which ends the stalled answers
	addr := ln.Addr().String()

	download := func(client string) net.Conn {
		t.Helper()
		c, err := net.Dial("tcp", addr)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = c.Close() })
		_, _ = fmt.Fprintf(c, "GET /big.bin HTTP/1.1\r\nHost: relay\r\nX-Test-IP: %s\r\n\r\n", client)
		select {
		case <-ln.stalled:
		case <-time.After(30 * time.Second):
			t.Fatalf("%s's answer never began", client)
		}
		return c
	}
	var first net.Conn
	for i := range lim.PlainPerNet {
		c := download(fmt.Sprintf("2001:db8:a:%x::1", i/lim.PlainPerIP))
		if i == 0 {
			first = c
		}
	}
	// A /64 of the same /48 that holds none yet is refused all the same.
	if code := ask(t, addr, "/big.bin", "2001:db8:a:ff::1"); code != http.StatusServiceUnavailable {
		t.Fatalf("one /48's connection over PlainPerNet: %d", code)
	}
	if !testcheck.Eventually(func() bool { s.mu.Lock(); defer s.mu.Unlock(); return len(s.plain.conns) == lim.PlainPerNet }) {
		t.Fatal("the refused connection still counts")
	}
	// Two more networks fill the pool.
	for i := range lim.PlainPerNet {
		download(fmt.Sprintf("2001:db8:b:%x::1", i/lim.PlainPerIP))
	}
	for range lim.Total - 2*lim.PlainPerNet {
		download("2001:db8:c::1")
	}
	quiet := keyOf("2001:db8:c::1", 48)
	s.mu.Lock()
	full, held := len(s.plain.conns), s.plain.nets[quiet]
	s.mu.Unlock()
	if full != lim.Total || held != 8 {
		t.Fatalf("%d of %d open, %d from the quiet /48", full, lim.Total, held)
	}

	if code := ask(t, addr, "/healthz", "203.0.113.9"); code != http.StatusOK {
		t.Fatalf("an unrelated client: %d", code)
	}
	// The one that made way is the crowded networks' longest-running answer.
	if err := first.SetReadDeadline(time.Now().Add(30 * time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err := io.Copy(io.Discard, first); errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatal("the oldest answer from the most crowded /48 stayed")
	}
	l, d := pair(t, "ws://"+addr, newKey())
	send(t, d, "through")
	expect(t, l, "through")
	s.mu.Lock()
	full, held = len(s.plain.conns), s.plain.nets[quiet]
	s.mu.Unlock()
	if full > lim.Total || held != 8 {
		t.Fatalf("%d of %d open, %d from the quiet /48 (want all 8 kept)", full, lim.Total, held)
	}
}

// fakeConn is a connection that says whether it was closed.
type fakeConn struct {
	net.Conn
	name   string
	closed bool
}

func (c *fakeConn) Close() error { c.closed = true; return nil }

// When Total are open, a fresh connection makes way first, then the one
// idle longest, then an answer: of the /48 holding the most, the one
// answering longest. A request that isn't answering (a WebSocket's
// upgrade) never does.
func TestMakeRoomOrder(t *testing.T) {
	s := New(Defaults).(*server)
	t0 := time.Now()
	var conns []*fakeConn
	add := func(name, net string, pc plainConn) {
		c := &fakeConn{name: name}
		pc.key, pc.net = "key-"+name, net
		if pc.fresh != nil {
			s.plain.fresh++
		}
		s.plain.conns[c] = &pc
		s.plain.nets[net]++
		conns = append(conns, c)
	}
	at := func(sec int) time.Time { return t0.Add(time.Duration(sec) * time.Second) }
	add("busy x 1", "x", plainConn{answer: at(1), since: at(1)})
	add("busy y", "y", plainConn{answer: at(0), since: at(0)}) // the oldest answer, alone in its /48
	add("busy x 2", "x", plainConn{answer: at(2), since: at(2)})
	add("upgrading x", "x", plainConn{since: at(-10)}) // the oldest of all
	add("idle 2", "z", plainConn{idle: true, since: at(5)})
	add("idle 1", "z", plainConn{idle: true, since: at(4)})
	add("fresh", "w", plainConn{idle: true, since: at(9), fresh: time.AfterFunc(time.Hour, func() {})})

	var order []string
	for {
		s.mu.Lock()
		ok := s.makeRoom()
		s.mu.Unlock()
		if !ok {
			break
		}
		for _, c := range conns {
			if c.closed && !slices.Contains(order, c.name) {
				order = append(order, c.name)
			}
		}
	}
	want := []string{"fresh", "idle 1", "idle 2", "busy x 1", "busy x 2", "busy y"}
	if fmt.Sprint(order) != fmt.Sprint(want) {
		t.Fatalf("made way in the order %q, want %q", order, want)
	}
	if len(s.plain.conns) != 1 || s.plain.fresh != 0 {
		t.Fatalf("%d left (want the upgrade), %d fresh", len(s.plain.conns), s.plain.fresh)
	}
}

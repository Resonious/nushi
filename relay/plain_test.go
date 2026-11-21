package relay

import (
	"bufio"
	"fmt"
	"net"
	"net/http"
	"testing"
)

// The plain connections' counts key an IPv6 address by its /64 (PlainPerIP)
// and its /48 (PlainPerNet); an IPv4 address is its own /48 too.
func TestPlainKeys(t *testing.T) {
	same := func(a, b string, bits int) bool { return keyOf(a, bits) == keyOf(b, bits) }
	for _, c := range []struct {
		a, b string
		bits int
		want bool
	}{
		{"[2001:db8:1:2::1]:443", "2001:db8:1:2:ffff::9", 64, true},
		{"2001:db8:1:2::1", "2001:db8:1:3::1", 64, false},
		{"2001:db8:1:2::1", "2001:db8:1:ffff::1", 48, true},
		{"2001:db8:1::1", "2001:db8:2::1", 48, false},
		{"203.0.113.7:9", "203.0.113.7", 48, true},
		{"203.0.113.7", "203.0.113.8", 48, false},
		{"::ffff:203.0.113.7", "203.0.113.7", 48, true},
	} {
		if got := same(c.a, c.b, c.bits); got != c.want {
			t.Errorf("%s and %s share a /%d key: %v, want %v", c.a, c.b, c.bits, got, c.want)
		}
	}
}

// PlainPerNet is never under PlainPerIP (an IPv4 address is both) nor over
// half of Total, and 0 is that half.
func TestPlainPerNetBounds(t *testing.T) {
	for _, c := range []struct{ perNet, perIP, total, want int }{
		{64, 8, 1000, 64},
		{0, 8, 1000, 500},
		{4, 8, 1000, 8},
		{64, 32, 1000, 64},
		{64, 8, 40, 20},
		{2000, 8, 1000, 500},
	} {
		got := New(Limits{PlainPerNet: c.perNet, PlainPerIP: c.perIP, Total: c.total}).(*server).lim.PlainPerNet
		if got != c.want {
			t.Errorf("PlainPerNet %d, PlainPerIP %d, Total %d: %d, want %d", c.perNet, c.perIP, c.total, got, c.want)
		}
	}
}

// ask sends one request on a new connection to addr as if from client
// (through the loopback proxy's X-Test-IP header) and gives its status,
// keeping the connection open until the test ends.
func ask(t *testing.T, addr, path, client string) int {
	t.Helper()
	c, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = c.Close() })
	_, _ = fmt.Fprintf(c, "GET %s HTTP/1.1\r\nHost: relay\r\nX-Test-IP: %s\r\n\r\n", path, client) // a refusal may close it first: the status says
	resp, err := http.ReadResponse(bufio.NewReader(c), nil)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	return resp.StatusCode
}

// Plain connections from one IPv6 /48 are counted together: its /64s, each
// under PlainPerIP, can't take more than PlainPerNet of them.
func TestPlainPerNet(t *testing.T) {
	lim := Defaults
	lim.IPHeader = "X-Test-IP"
	lim.PlainPerIP, lim.PlainPerNet = 2, 5
	lim.NewRate = 1e9
	addr := plainServer(t, lim)
	for i := range 5 {
		if code := ask(t, addr, "/healthz", fmt.Sprintf("2001:db8:1:%x::1", i/2)); code != http.StatusOK {
			t.Fatalf("connection %d of one /48 refused (%d) under its cap", i, code)
		}
	}
	if code := ask(t, addr, "/healthz", "2001:db8:1:ff::1"); code != http.StatusServiceUnavailable {
		t.Errorf("a sixth connection from one /48, from a /64 of its own: %d", code)
	}
	if code := ask(t, addr, "/healthz", "2001:db8:2::1"); code != http.StatusOK {
		t.Errorf("another /48: %d", code)
	}
}

package listeners

import (
	"net"
	"net/netip"
	"os"
	"slices"
	"strconv"
	"testing"

	"golang.org/x/sys/windows"

	"github.com/afrase/nushi/internal/testcheck"
)

// These tests check what is Windows' own; the rest are in
// listeners_test.go and tcptable_test.go.

// Without GetExtendedTcpTable (a system that lacks it, as here a name
// iphlpapi doesn't have), List fails, where calling it would panic.
func TestListWithoutTheTable(t *testing.T) {
	had := getExtendedTCPTable
	t.Cleanup(func() { getExtendedTCPTable = had })
	getExtendedTCPTable = windows.NewLazySystemDLL("iphlpapi.dll").NewProc("NushiNoSuchFunction")
	if _, err := List(); err == nil {
		t.Error("List didn't fail")
	}
}

// TestListReadsMany lists every listener of a process holding more than
// the table's first buffer has room for (4096 bytes: 170 IPv4 rows).
func TestListReadsMany(t *testing.T) {
	pid, ports := listenElsewhere(t, slices.Repeat([]string{"ipv4"}, 200)...)
	ls, err := List()
	testcheck.NoErr(t, err)
	if got := ofPid(ls, pid); len(got) != len(ports) {
		t.Fatalf("listed %d of the helper's %d listeners", len(got), len(ports))
	}
}

// A process's IPv4 wildcard and its own IPv6-only one on the same port
// are listed as one dual-stack listener: the table lists a dual-stack
// socket as both, and doesn't tell them apart (tableListeners). That
// listener takes what the two do: each family's connections, to that
// process, as dials to both show.
func TestListMergesAProcesssTwoWildcards(t *testing.T) {
	v4, err := net.Listen("tcp4", "0.0.0.0:0") //nolint:gosec // the wildcard is what's tested, closed at the test's end
	testcheck.NoErr(t, err)
	defer func() { _ = v4.Close() }()
	port := v4.Addr().(*net.TCPAddr).Port
	v6, err := net.Listen("tcp6", net.JoinHostPort("::", strconv.Itoa(port))) // Go sets IPV6_V6ONLY on it
	if err != nil {
		t.Skipf("no IPv6 wildcard beside the IPv4 one: %v", err)
	}
	defer func() { _ = v6.Close() }()
	p := uint16(port) //nolint:gosec // a port
	got := ofPid(onPort(list(t), p), os.Getpid())
	want := Listener{Pid: os.Getpid(), Addr: netip.AddrPortFrom(netip.IPv6Unspecified(), p), DualStack: true}
	if len(got) != 1 || got[0] != want {
		t.Fatalf("listed %v, want only %v", got, want)
	}
	for _, host := range []string{"127.0.0.1", "::1"} {
		dst := netip.AddrPortFrom(netip.MustParseAddr(host), p)
		if reach := Reaching(got, dst); len(reach) != 1 {
			t.Errorf("reaching %v: %v", dst, reach)
		}
		c, err := net.Dial("tcp", dst.String())
		if err != nil {
			t.Errorf("a dial to %v failed: %v", dst, err)
			continue
		}
		_ = c.Close()
	}
}

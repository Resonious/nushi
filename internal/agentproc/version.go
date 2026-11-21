package agentproc

import (
	"context"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/afrase/nushi/internal/procgroup"
)

// Version is what `bin --version` printed, trimmed: a bridge's check of
// the program it speaks to (Ante's host, pi). It has 10 s.
func Version(bin string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, "--version")
	procgroup.Bound(cmd)
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("couldn't run %s --version: %w", bin, err)
	}
	return strings.TrimSpace(string(out)), nil
}

// Numbers reads a version's three numbers, a prerelease's tag left out;
// nil if it hasn't three.
func Numbers(v string) []int {
	v, _, _ = strings.Cut(v, "-")
	parts := strings.Split(v, ".")
	if len(parts) != 3 {
		return nil
	}
	out := make([]int, 3)
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil {
			return nil
		}
		out[i] = n
	}
	return out
}

package githubapi

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// hunkLines is how many of a review thread's diff lines are kept: GitHub's
// page shows a few above the comment, and a hunk can run to thousands.
const hunkLines = 20

// hunkLineBytes is where a diff line is cut (a minified file's line).
const hunkLineBytes = 400

var hunkHeader = regexp.MustCompile(`^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$`)

// TailHunk is a unified diff hunk's last n lines (a review comment's
// diffHunk ends at its line), each cut at 400 bytes, under its @@ header
// counted again for the lines kept, so the first kept line's numbers are
// still known. GitHub's header counts the whole hunk, past the comment's
// line where it cut the text (docs/facts/github.md), so it is counted
// again even when no line goes. A hunk without a header it reads keeps
// its last n lines.
func TailHunk(hunk string, n int) string {
	if hunk == "" {
		return ""
	}
	lines := strings.Split(strings.TrimSuffix(hunk, "\n"), "\n")
	m := hunkHeader.FindStringSubmatch(lines[0])
	if m == nil {
		return cutLines(lines[max(0, len(lines)-n):])
	}
	oldAt, _ := strconv.Atoi(m[1])
	newAt, _ := strconv.Atoi(m[2])
	body := lines[1:]
	dropped := body[:max(0, len(body)-n)]
	body = body[len(dropped):]
	for _, l := range dropped {
		inOld, inNew := hunkSides(l)
		if inOld {
			oldAt++
		}
		if inNew {
			newAt++
		}
	}
	var oldCount, newCount int
	for _, l := range body {
		inOld, inNew := hunkSides(l)
		if inOld {
			oldCount++
		}
		if inNew {
			newCount++
		}
	}
	header := fmt.Sprintf("@@ -%d,%d +%d,%d @@%s", oldAt, oldCount, newAt, newCount, m[3])
	return header + "\n" + cutLines(body)
}

// hunkSides says which sides a hunk's line is on: a removed line the old
// one's, an added line the new one's, context both, and "\ No newline at
// end of file" neither.
func hunkSides(line string) (inOld, inNew bool) {
	switch {
	case strings.HasPrefix(line, "-"):
		return true, false
	case strings.HasPrefix(line, "+"):
		return false, true
	case strings.HasPrefix(line, `\`):
		return false, false
	}
	return true, true
}

func cutLines(lines []string) string {
	var b strings.Builder
	for i, l := range lines {
		if i > 0 {
			b.WriteByte('\n')
		}
		if len(l) > hunkLineBytes {
			l = strings.ToValidUTF8(l[:hunkLineBytes], "")
		}
		b.WriteString(l)
	}
	return b.String()
}

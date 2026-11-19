// Package dartcheck is what the repository's checks of the app's Dart
// share (tools/design-check, tools/native-edge): a line that breaks one,
// protoc's and Connect's code left out, and the run over each root that
// prints them.
package dartcheck

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Use is one line of a file that breaks a check.
type Use struct {
	Path string
	Line int
	What string
}

// generated are the suffixes of protoc's and Connect's Dart.
var generated = []string{".pb.dart", ".pbenum.dart", ".pbjson.dart", ".pbserver.dart", ".pbgrpc.dart"}

// Generated says whether path is protoc's or Connect's Dart, which the
// checks leave out.
func Generated(path string) bool {
	base := filepath.Base(path)
	for _, s := range generated {
		if strings.HasSuffix(base, s) {
			return true
		}
	}
	return strings.Contains(base, ".connect.")
}

// Run is a check's main, which exits with what it returns: check over
// each root the command line names (app/lib when none), each use printed
// and then hint, and 1 if there's one; an error, named for the command,
// is 2.
func Run(command, hint string, check func(root string) ([]Use, error)) int {
	roots := os.Args[1:]
	if len(roots) == 0 {
		roots = []string{"app/lib"}
	}
	var uses []Use
	for _, root := range roots {
		found, err := check(root)
		if err != nil {
			fmt.Fprintln(os.Stderr, command+":", err)
			return 2
		}
		uses = append(uses, found...)
	}
	for _, u := range uses {
		fmt.Fprintf(os.Stderr, "%s:%d: %s\n", u.Path, u.Line, u.What)
	}
	if len(uses) > 0 {
		fmt.Fprintln(os.Stderr, hint)
		return 1
	}
	return 0
}

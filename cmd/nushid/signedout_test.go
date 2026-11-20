package main

import (
	"errors"
	"fmt"
	"testing"

	acp "github.com/afrase/acp-go/unstable"
)

// A start refused for want of a sign-in says how to sign in, not the
// agent's error code; any other failure is explained as before.
func TestSignedOut(t *testing.T) {
	explain := func(err error) error { return fmt.Errorf("%w (explained)", err) }
	refused := fmt.Errorf("session/new: %w", &acp.Error{Code: acp.ErrorCodeAuthenticationRequired, Message: "Authentication required"})
	for _, c := range []struct {
		signIn string
		err    error
		want   string
	}{
		{"codex login", refused, "it isn't signed in. Run codex login in a terminal, then start the chat again."},
		{"", refused, "it isn't signed in. Sign in with its CLI in a terminal, then start the chat again."},
		{"codex login", errors.New("initialize: it quit"), "initialize: it quit (explained)"},
		{"codex login", fmt.Errorf("session/new: %w", &acp.Error{Code: acp.ErrorCodeInternalError, Message: "Internal error"}), ""},
	} {
		got := signedOut(c.signIn, explain)(c.err)
		if !errors.Is(got, c.err) {
			t.Errorf("%v: lost the agent's error", got)
		}
		if c.want == "" {
			c.want = c.err.Error() + " (explained)"
		}
		if got.Error() != c.want {
			t.Errorf("signIn %q: %q, want %q", c.signIn, got, c.want)
		}
	}
}

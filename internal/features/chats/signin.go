package chats

import (
	"errors"
	"slices"

	acp "github.com/afrase/acp-go/unstable"

	"github.com/afrase/nushi/internal/model"
)

// SignInError is a start or reopen the agent refused because it isn't
// signed in (ACP's Authentication required), with the ways it offers to
// sign itself in that Nushi can run (signInMethods), never empty: the app
// offers them. ADR 0145.
type SignInError struct {
	Agent   string         // the agent's name
	Methods []model.Option // each one's ID, Name and Description, as the agent gives them
	Err     error
}

func (e *SignInError) Error() string { return e.Err.Error() }
func (e *SignInError) Unwrap() error { return e.Err }

// authRequired says the agent refused err's request with ACP's
// Authentication required.
func authRequired(err error) bool {
	e, ok := errors.AsType[*acp.Error](err)
	return ok && e.Code == acp.ErrorCodeAuthenticationRequired
}

// signInError is err as a SignInError when it is an Authentication
// required and the agent, as it initialized (init), offers a way to sign in
// that Nushi can run; else err.
func (k *kind) signInError(init *acp.InitializeResponse, err error) error {
	if !authRequired(err) {
		return err
	}
	methods := k.signInMethods(init)
	if len(methods) == 0 {
		return err
	}
	return &SignInError{Agent: k.Name, Methods: methods, Err: err}
}

// Meta keys of an auth method that has the client supply what it signs in
// with: an API key (codex-acp's "api-key", whose key is the request's or
// the environment's) or a model gateway's address and key ("gateway").
var clientSupplied = []string{"api-key", "gateway"}

// signInMethods are the ways the agent (as it initialized) signs itself in
// that Nushi offers: only ACP's agent methods, which the agent runs by
// itself through authenticate (Codex's ChatGPT sign-in opens the browser);
// not a terminal method, nor a type acp-go doesn't know (an environment
// variable's), nor one whose _meta asks the client for a key or a gateway,
// nor one the agent's Kind leaves out (NoSignIn). Nushi never handles the
// user's keys. ADR 0145.
func (k *kind) signInMethods(init *acp.InitializeResponse) []model.Option {
	if init == nil {
		return nil
	}
	var out []model.Option
	for _, m := range init.AuthMethods {
		a := m.Agent
		if a == nil || a.ID == "" || slices.Contains(k.NoSignIn, string(a.ID)) ||
			slices.ContainsFunc(clientSupplied, func(key string) bool { _, ok := a.Meta[key]; return ok }) {
			continue
		}
		out = append(out, model.Option{ID: string(a.ID), Name: a.Name, Description: a.Description})
	}
	return out
}

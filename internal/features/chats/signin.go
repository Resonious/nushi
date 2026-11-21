package chats

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"time"

	acp "github.com/afrase/acp-go/unstable"

	"github.com/afrase/nushi/internal/model"
)

// SignInError is a start or reopen the agent refused because it isn't
// signed in (ACP's Authentication required), with the ways it offers to
// sign itself in that Nushi can run (signInMethods), never empty: the app
// offers them, and SignIn runs the one picked. ADR 0145.
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

// SignInTimeout bounds a sign-in: the user is in a browser meanwhile.
var SignInTimeout = 10 * time.Minute

// authenticator is an agent that takes ACP's authenticate, as an agent's
// process (agentproc.Agent) does.
type authenticator interface {
	Authenticate(ctx context.Context, req *acp.AuthenticateRequest) (*acp.AuthenticateResponse, error)
}

// signInClient is the client side of a sign-in's agent: it opens no
// session, so it answers nothing.
type signInClient struct{ acp.UnimplementedClient }

// SignIn signs the agent named agent in through method, one of the ways
// it offers (SignInError.Methods): a process of the agent, started as a
// chat's is (the same Launch, so as its settings say now), is asked to
// authenticate, and stopped, with its process group, once it has answered,
// or when ctx ends or SignInTimeout passes, which ends its login. The agent
// runs its own login: Codex opens the browser and waits for the user.
// One sign-in at a time for each agent. Once it is signed in, its chats
// whose reopen failed for want of it may reopen when next shown.
func (s *Service) SignIn(ctx context.Context, agent, method string) error {
	k, err := s.kindOf(agent)
	if err != nil {
		return err
	}
	s.mu.Lock()
	if s.signingIn[k.Name] {
		s.mu.Unlock()
		return fmt.Errorf("%s is signing in already: finish in the browser, or cancel that first", k.Title)
	}
	if s.signingIn == nil {
		s.signingIn = map[string]bool{}
	}
	s.signingIn[k.Name] = true
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.signingIn, k.Name)
		s.mu.Unlock()
	}()
	ctx, cancel := context.WithTimeout(ctx, SignInTimeout)
	defer cancel()
	log := slog.With("agent", k.Name, "for", "sign-in")
	a, init, err := initialize(ctx, k, signInClient{}, log)
	if err != nil {
		return k.explain(err)
	}
	defer func() { _ = a.Close() }() // its group, and with it a login still waiting
	if !slices.ContainsFunc(k.signInMethods(init), func(o model.Option) bool { return o.ID == method }) {
		return fmt.Errorf("%s doesn't offer that way to sign in", k.Title)
	}
	auth, ok := a.(authenticator)
	if !ok {
		return fmt.Errorf("%s can't be signed in from Nushi", k.Title)
	}
	log.Info("agent signing in", "method", method)
	if _, err := auth.Authenticate(ctx, &acp.AuthenticateRequest{MethodID: acp.AuthMethodID(method)}); err != nil {
		log.Warn("agent not signed in", "err", err)
		return signInFailed(ctx, k.Title, err)
	}
	log.Info("agent signed in")
	s.signedIn(k.Name)
	return nil
}

// signInFailed is a sign-in's error in plain words: the agent's own
// message without its code, or that it took too long; a cancelled call's
// own error, as the API passes it on.
func signInFailed(ctx context.Context, title string, err error) error {
	switch {
	case errors.Is(ctx.Err(), context.DeadlineExceeded):
		return fmt.Errorf("%s didn't finish signing in within %d minutes: %w", title, int(SignInTimeout.Minutes()), err)
	case ctx.Err() != nil:
		return ctx.Err()
	}
	if e, ok := errors.AsType[*acp.Error](err); ok && e.Message != "" {
		return fmt.Errorf("%s didn't sign in: %s", title, e.Message)
	}
	return fmt.Errorf("%s didn't sign in: %w", title, err)
}

// signedIn is the agent named agent signed in: its chats whose reopen
// failed for want of it may reopen, each when it's next shown (Reopen), as
// AgentReady has them.
func (s *Service) signedIn(agent string) {
	for _, c := range s.openChats() {
		c.mu.Lock()
		if f := c.failureLocked(); c.kind.Name == agent && c.reopenFailed && f != nil && f.Status == "sign_in" {
			c.reopenFailed = false
			c.statusChangedLocked()
			c.logLocked().Info("chat may reopen", "why", "agent signed in")
		}
		c.mu.Unlock()
	}
}

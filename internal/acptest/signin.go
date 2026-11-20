package acptest

import (
	"encoding/json"
	"sync"
)

// SignIn puts the agents that share it behind a login, as Codex with none
// is: they advertise codex-acp's auth methods (an API key and a gateway,
// with their _meta, ChatGPT, and ChatGPT's device code), refuse
// session/new and session/load with ACP's Authentication required
// (-32000) until one of them has been signed in, and sign in through
// authenticate, which waits, as a browser login does, for Finish or for its
// connection to end.
type SignIn struct {
	Finish chan error    // each authenticate waits for one: nil signs in
	Begun  chan string   // gets each authenticate's method as it begins, when set (buffered)
	Ended  chan struct{} // gets one as an authenticate's connection ends while it waits, when set (buffered)

	mu sync.Mutex
	in bool
}

// SignedIn says whether an agent has been signed in.
func (s *SignIn) SignedIn() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.in
}

// SignOut signs the agents out again.
func (s *SignIn) SignOut() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.in = false
}

// signInMethods are codex-acp's auth methods, as 0.17 advertises them to
// a client without URL elicitation (the device code's besides, which the
// Go agent may advertise).
var signInMethods = []map[string]any{
	{"id": "api-key", "name": "API Key", "description": "Use an API key to authenticate", "_meta": map[string]any{"api-key": map[string]any{"provider": "openai"}}},
	{"id": "chat-gpt", "name": "ChatGPT", "description": "Use ChatGPT to authenticate"},
	{"id": "chat-gpt-device-code", "name": "ChatGPT (device code)"},
	{"id": "gateway", "name": "Custom model gateway", "_meta": map[string]any{"gateway": map[string]any{"protocol": "openai"}}},
}

// withSignIn is initialize's result, with the auth methods when the agent
// is behind a login.
func (a *Agent) withSignIn(result any) any {
	if m, ok := result.(map[string]any); ok && a.SignIn != nil {
		m["authMethods"] = signInMethods
	}
	return result
}

// signInAnswered answers f when the login has the answer: authenticate,
// or a session/new or load while the agent isn't signed in (Authentication
// required), and says whether it did.
func (a *Agent) signInAnswered(f frame) bool {
	switch {
	case f.Method == "authenticate":
		go a.authenticate(f) // it waits, as a login does
	case f.Method != "session/new" && f.Method != "session/load", a.SignIn == nil, a.SignIn.SignedIn():
		return false
	default:
		a.send(frame{ID: f.ID, Error: &rpcError{Code: -32000, Message: "Authentication required"}})
	}
	return true
}

// authenticate answers authenticate: a method it advertises, once Finish
// says how it went; nothing once its connection has ended.
func (a *Agent) authenticate(f frame) {
	var req struct {
		MethodID string `json:"methodId"`
	}
	_ = json.Unmarshal(f.Params, &req)
	s := a.SignIn
	known := false
	for _, m := range signInMethods {
		known = known || m["id"] == req.MethodID
	}
	if s == nil || !known {
		a.send(frame{ID: f.ID, Error: &rpcError{Code: -32600, Message: "Invalid request"}})
		return
	}
	if s.Begun != nil {
		s.Begun <- req.MethodID
	}
	select {
	case err := <-s.Finish:
		if err != nil {
			a.send(frame{ID: f.ID, Error: &rpcError{Code: -32000, Message: err.Error()}})
			return
		}
		s.mu.Lock()
		s.in = true
		s.mu.Unlock()
		a.send(frame{ID: f.ID, Result: json.RawMessage(`{}`)})
	case <-a.served:
		if s.Ended != nil {
			s.Ended <- struct{}{}
		}
	}
}

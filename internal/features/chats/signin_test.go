package chats

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"testing"

	acp "github.com/afrase/acp-go/unstable"

	"github.com/afrase/nushi/internal/model"
	"github.com/afrase/nushi/internal/testcheck"
)

// signInFake is fakeAgent behind a login, as Codex with none is: each of
// its processes advertises codex-acp's auth methods (and a terminal one,
// and a type acp-go doesn't know), and refuses session/new and load with
// ACP's Authentication required until it is signed in.
type signInFake struct {
	*fakeAgent
	methods []acp.AuthMethod // advertised; nil: codexMethods

	mu       sync.Mutex
	signedIn bool
}

func newSignInFake() *signInFake {
	return &signInFake{fakeAgent: &fakeAgent{}}
}

// codexMethods are codex-acp's methods, as it advertises them (api-key and
// gateway with their _meta), with ones Nushi must leave out besides.
func codexMethods(t *testing.T) []acp.AuthMethod {
	t.Helper()
	var out []acp.AuthMethod
	testcheck.NoErr(t, json.Unmarshal([]byte(`[
		{"id":"api-key","name":"API Key","_meta":{"api-key":{"provider":"openai"}}},
		{"id":"chat-gpt","name":"ChatGPT","description":"Use ChatGPT to authenticate"},
		{"id":"chat-gpt-device-code","name":"ChatGPT (device code)"},
		{"id":"gateway","name":"Custom model gateway","_meta":{"gateway":{"protocol":"openai"}}},
		{"id":"key-env","name":"Key","_meta":{"api-key":{}}},
		{"type":"terminal","id":"tui","name":"In a terminal"},
		{"type":"env_var","id":"env","name":"From the environment"}
	]`), &out))
	return out
}

// kindFor is the fake's Kind: its processes are signInProcs.
func (f *signInFake) kindFor(noSignIn ...string) Kind {
	return Kind{Harness: model.HarnessInfo{Name: "fake", Title: "Fake"}, NoSignIn: noSignIn, Launch: func(h acp.Client, log *slog.Logger) (Agent, error) {
		a, err := f.launch(h, log)
		if err != nil {
			return nil, err
		}
		return &signInProc{proc: a.(*proc), f: f}, nil
	}}
}

// signInProc is one of the fake's processes.
type signInProc struct {
	*proc
	f *signInFake
}

func (p *signInProc) Initialize(ctx context.Context, req *acp.InitializeRequest) (*acp.InitializeResponse, error) {
	resp, err := p.proc.Initialize(ctx, req)
	if err == nil {
		resp.AuthMethods = p.f.methods
	}
	return resp, err
}

func (p *signInProc) refused() error {
	p.f.mu.Lock()
	defer p.f.mu.Unlock()
	if p.f.signedIn {
		return nil
	}
	return &acp.Error{Code: acp.ErrorCodeAuthenticationRequired, Message: "Authentication required"}
}

func (p *signInProc) NewSession(ctx context.Context, req *acp.NewSessionRequest) (*acp.NewSessionResponse, error) {
	if err := p.refused(); err != nil {
		return nil, err
	}
	return p.proc.NewSession(ctx, req)
}

func (p *signInProc) LoadSession(ctx context.Context, req *acp.LoadSessionRequest) (*acp.LoadSessionResponse, error) {
	if err := p.refused(); err != nil {
		return nil, err
	}
	return p.proc.LoadSession(ctx, req)
}

func (f *signInFake) signOut() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.signedIn = false
}

// A new chat whose agent isn't signed in fails to start, saying the ways
// to sign in Nushi can run: the agent's own, none taking a key or needing
// what Nushi can't show (NoSignIn).
func TestStartWantsSignIn(t *testing.T) {
	f := newSignInFake()
	f.methods = codexMethods(t)
	svc := newService(t, []Kind{f.kindFor("chat-gpt-device-code")}, Options{})
	_, err := svc.Start(t.Context(), "", t.TempDir(), false)
	in, ok := errors.AsType[*SignInError](err)
	if !errors.Is(err, ErrStart) || !ok || in.Agent != "fake" {
		t.Fatalf("Start = %v", err)
	}
	if want := []model.Option{{ID: "chat-gpt", Name: "ChatGPT", Description: "Use ChatGPT to authenticate"}}; !slices.Equal(in.Methods, want) {
		t.Errorf("methods %+v, want %+v", in.Methods, want)
	}
	// None it can run: the plain error, as before.
	f.methods = f.methods[:1]
	if _, err := svc.Start(t.Context(), "", t.TempDir(), false); errors.As(err, new(*SignInError)) || !authRequired(err) {
		t.Errorf("Start with only a key's method = %v", err)
	}
}

// A sleeping chat whose agent signed out says so as it wakes for a
// message, which stays queued; once signed in, the chat reopens when shown
// and the message goes.
func TestWakeWantsSignIn(t *testing.T) {
	f := newSignInFake()
	f.methods = codexMethods(t)
	f.updates = []acp.SessionUpdate{chunk("m1", "ok")}
	f.signedIn = true
	svc := newService(t, []Kind{f.kindFor("chat-gpt-device-code")}, Options{})
	c := startChat(t, svc, t.TempDir())
	turn(t, svc, c, "one")
	testcheck.NoErr(t, svc.Sleep(c.id))
	f.signOut()
	testcheck.NoErr(t, svc.Prompt(t.Context(), c.id, model.Message{Text: "two"}, SendIdle))
	eventually(t, c, func() bool { f := c.failureLocked(); return f != nil && f.Status == "sign_in" })
	c.mu.Lock()
	notice, queued := *c.failureLocked(), len(c.queue)
	c.mu.Unlock()
	if len(notice.Options) != 1 || notice.Options[0].ID != "chat-gpt" || !strings.Contains(notice.Text, "Authentication required") || queued != 1 {
		t.Fatalf("notice %+v, %d queued", notice, queued)
	}

	f.mu.Lock()
	f.signedIn = true
	f.mu.Unlock()
	testcheck.NoErr(t, svc.Reopen(c.id))
	eventually(t, c, func() bool { return c.agent != nil && len(c.queue) == 0 && !c.busy })
	f.fakeAgent.mu.Lock()
	prompts := slices.Clone(f.prompts)
	f.fakeAgent.mu.Unlock()
	if !slices.Equal(prompts, []string{"one", "two"}) || !slices.Contains(texts(c), "user:two") {
		t.Errorf("after signing in: prompts %q, %q", prompts, texts(c))
	}
}

package api

import (
	"path/filepath"
	"testing"

	"connectrpc.com/connect"

	"github.com/afrase/nushi/internal/features/chats"
	"github.com/afrase/nushi/internal/features/trust"
	nushiv1 "github.com/afrase/nushi/internal/gen/nushi/v1"
	"github.com/afrase/nushi/internal/model"
	"github.com/afrase/nushi/internal/store"
	"github.com/afrase/nushi/internal/testcheck"
)

// The phone checks and remembers trust using the same typed path it starts with.
func TestHomeChatFolder(t *testing.T) {
	home := t.TempDir()
	project := filepath.Join(home, "my project")
	hook := filepath.Join(project, ".claude", "settings.json")
	testcheck.Write(t, hook, `{"hooks":{}}`)
	st := store.New(t.TempDir())
	kinds := []chats.Kind{{Harness: model.HarnessInfo{Name: "a"}}}
	svc := chats.New(t.Context(), kinds, chats.Options{Remembered: st, Sessions: st, Scratch: t.TempDir()})
	t.Cleanup(svc.Close)
	s := server{Services{Home: home, Chats: svc, Trust: trust.New(map[string]trust.Agent{"a": hookAgent{}}, st)}}
	for input, want := range map[string]string{
		"~": home, "~/": home, "~/my project": project, filepath.Join("~", "my project"): project,
		"": "", project: project, "relative": "relative", "~user": "~user", "p/~": "p/~",
	} {
		if got := s.chatFolder(input); got != want {
			t.Errorf("chatFolder(%q) = %q, want %q", input, got, want)
		}
	}
	req := connect.NewRequest(&nushiv1.CheckFolderRequest{Agent: "a", Folder: "~/my project"})
	checked, err := s.CheckFolder(t.Context(), req)
	testcheck.NoErr(t, err)
	if runs := checked.Msg.Runs; len(runs) != 1 || runs[0].File != hook {
		t.Fatalf("trust card runs = %v", runs)
	}
	_, err = s.TrustFolder(t.Context(), connect.NewRequest(&nushiv1.TrustFolderRequest{Agent: "a", Folder: req.Msg.Folder, Key: checked.Msg.Key}))
	testcheck.NoErr(t, err)
	req.Msg.Folder = project
	checked, err = s.CheckFolder(t.Context(), req)
	testcheck.NoErr(t, err)
	if len(checked.Msg.Runs) != 0 {
		t.Fatal("the absolute path still asks for trust")
	}
}

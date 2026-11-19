package agyskills

import (
	"context"
	"path/filepath"
	"strings"
	"testing"

	"github.com/afrase/nushi/internal/testcheck"
)

func setHome(t *testing.T, home string) {
	t.Helper()
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)
}

func writeSkill(t *testing.T, root, dir, name, desc string) string {
	t.Helper()
	p := filepath.Join(root, dir)
	testcheck.Write(t, filepath.Join(p, "SKILL.md"), "---\nname: "+name+"\ndescription: "+desc+"\n---\nBody\n")
	return p
}

func TestList(t *testing.T) {
	home := t.TempDir()
	setHome(t, home)
	repo := filepath.Join(home, "repo")
	sub := filepath.Join(repo, "pkg")
	testcheck.Write(t, filepath.Join(repo, ".git", "HEAD"), "ref: refs/heads/main\n")

	// Nearest project dir wins over repo root, and project wins over user.
	writeSkill(t, filepath.Join(sub, ".agents", "skills"), "shared-one", "shared-one", "from sub")
	writeSkill(t, filepath.Join(repo, ".agents", "skills"), "shared-one", "shared-one", "shadowed from root")
	writeSkill(t, filepath.Join(repo, ".agent", "skills"), "proj-one", "proj-one", "from .agent")
	writeSkill(t, filepath.Join(repo, "_agents", "skills"), "under-one", "under-one", "from _agents")
	writeSkill(t, filepath.Join(home, ".gemini", "config", "skills"), "mine", "mine", "global skill")
	writeSkill(t, filepath.Join(home, ".gemini", "config", "skills"), "proj-one", "proj-one", "shadowed global")

	got, err := (Agy{}).List(context.Background(), sub)
	testcheck.NoErr(t, err)
	if !got.ReadsShared || got.NoSwitch == "" {
		t.Fatalf("ReadsShared=%v NoSwitch=%q", got.ReadsShared, got.NoSwitch)
	}
	var lines []string
	for _, s := range got.Skills {
		lines = append(lines, s.Source+" "+s.Name+" "+s.State+" "+s.Description)
	}
	want := strings.Join([]string{
		"shared shared-one on from sub",
		"project proj-one on from .agent",
		"project under-one on from _agents",
		"user mine on global skill",
	}, "|")
	if strings.Join(lines, "|") != want {
		t.Errorf("skills:\n  %s\nwant:\n  %s", strings.Join(lines, "|"), want)
	}
}

func TestSetSkillOnRefused(t *testing.T) {
	if err := (Agy{}).SetSkillOn(context.Background(), t.TempDir(), "user", "mine", false); err == nil {
		t.Fatal("SetSkillOn succeeded, want refusal")
	}
}

func TestCanTrash(t *testing.T) {
	home := t.TempDir()
	setHome(t, home)
	repo := filepath.Join(home, "repo")
	testcheck.Write(t, filepath.Join(repo, ".git", "HEAD"), "ref: refs/heads/main\n")

	proj := writeSkill(t, filepath.Join(repo, ".agent", "skills"), "p", "p", "proj")
	shared := writeSkill(t, filepath.Join(repo, ".agents", "skills"), "s", "s", "shared")
	user := writeSkill(t, filepath.Join(home, ".gemini", "config", "skills"), "u", "u", "user")

	a := Agy{}
	if err := a.CanTrash(context.Background(), repo, proj); err != nil {
		t.Errorf("CanTrash(project): %v", err)
	}
	if err := a.CanTrash(context.Background(), repo, user); err != nil {
		t.Errorf("CanTrash(user): %v", err)
	}
	if err := a.CanTrash(context.Background(), repo, shared); err == nil {
		t.Errorf("CanTrash(shared) = nil, want refusal (shared is trashed by skills.Service)")
	}
}

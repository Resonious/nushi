package agy

import (
	"path/filepath"
	"reflect"
	"testing"

	"github.com/afrase/nushi/internal/model"
)

func TestInfo(t *testing.T) {
	want := model.HarnessInfo{
		Name:          "agy",
		Title:         "Antigravity",
		Resume:        "agy --conversation",
		ClientMCP:     true,
		NamesSessions: true,
	}
	if got := (Harness{}).Info(); !reflect.DeepEqual(got, want) {
		t.Fatalf("Info() = %+v, want %+v", got, want)
	}
	if got := (Local{}).Info(); !reflect.DeepEqual(got, want) {
		t.Fatalf("Local.Info() = %+v, want %+v", got, want)
	}
}

func TestOther(t *testing.T) {
	h := Harness{}
	q := model.Field{ID: "q1", Options: []model.Option{{ID: "1", Name: "Red"}}}
	for _, c := range []struct {
		name  string
		field model.Field
		want  bool
	}{
		{"matching other", model.Field{ID: "q1_other", Title: "Other"}, true},
		{"other with options", model.Field{ID: "q1_other", Options: []model.Option{{ID: "x"}}}, false},
		{"different question", model.Field{ID: "q2_other"}, false},
		{"different suffix", model.Field{ID: "q1_custom"}, false},
	} {
		if got := h.Other(c.field, q); got != c.want {
			t.Errorf("%s: Other = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestToolCall(t *testing.T) {
	h := Harness{}
	for _, c := range []struct {
		title, want string
	}{
		{"Run mcp_nushi_show", "mcp_nushi_show"},
		{"Run mcp_nushi_preview_start", "mcp_nushi_preview_start"},
		{"Run ask_question", "Run ask_question"},
		{"echo done", "echo done"},
	} {
		it := model.Item{Title: c.title}
		if h.ToolCall(&it, nil, nil) {
			t.Errorf("%q: ToolCall returned ownText=true", c.title)
		}
		if it.Title != c.want {
			t.Errorf("%q: title = %q, want %q", c.title, it.Title, c.want)
		}
	}
}

func TestConfigDir(t *testing.T) {
	home := filepath.Join(t.TempDir(), "home")
	want := filepath.Join(home, ".gemini", "config")
	if got := ConfigDir(home); got != want {
		t.Errorf("ConfigDir(%q) = %q, want %q", home, got, want)
	}
}

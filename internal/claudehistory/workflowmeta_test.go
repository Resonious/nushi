package claudehistory

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/afrase/nushi/internal/model"
	"github.com/afrase/nushi/internal/testcheck"
)

// The meta literal reads as data, in the forms a script writes it: names
// or quoted keys, any quote, comments, trailing commas, escapes.
func TestReadMeta(t *testing.T) {
	script := `// a run
export const meta = {
  name: 'sweep', // the name
  "description": "Look at \"each\" part",
  version: 2, ratio: -0.5, mask: 0x1f, on: true, off: null,
  phases: [
    { title: 'Map', detail: ` + "`all parts`" + ` },
    /* none */ { title: "Reviewé" },
    { detail: 'no title' },
    { title: 'Verify', detail: 'it\'s done', },
  ],
}
phase('Map')
`
	m, err := readMeta(script)
	testcheck.NoErr(t, err)
	want := scriptMeta{Name: "sweep", Description: `Look at "each" part`, Phases: []metaPhase{{"Map", "all parts"}, {"Reviewé", ""}, {"Verify", "it's done"}}}
	if !reflect.DeepEqual(m, want) {
		t.Errorf("got %+v", m)
	}
}

// Code in the literal, or no literal, is no meta: nothing of it is run.
func TestMetaThatIsCode(t *testing.T) {
	for _, script := range []string{
		`const x = 1`,
		`export const meta = { name: makeName() }`,
		`export const meta = { ...base, phases: [] }`,
		"export const meta = { name: `run ${n}` }",
		`export const meta = { phases }`,
		`export const meta = { [key]: 1 }`,
		`export const meta = { name: 'cut`,
		`export const meta = ` + strings.Repeat("[", 40) + strings.Repeat("]", 40),
	} {
		if m, err := readMeta(script); err == nil {
			t.Errorf("%q: %+v", script, m)
		}
	}
}

// The recorded script plans the two phases it then reached.
func TestRecordedMeta(t *testing.T) {
	scripts, _ := filepath.Glob(filepath.Join("..", "features", "chats", "testdata", "claude-parity", "workflow", "history", "end", "*", "workflows", "scripts", "*.js"))
	if len(scripts) != 1 {
		t.Fatalf("scripts: %v", scripts)
	}
	data, err := os.ReadFile(scripts[0])
	testcheck.NoErr(t, err)
	m, err := readMeta(string(data))
	testcheck.NoErr(t, err)
	if m.Name != "two-phases" || len(m.Phases) != 2 || m.Phases[1] != (metaPhase{"Review", "two more"}) {
		t.Errorf("got %+v", m)
	}
}

// While it runs, the phases its script plans and it hasn't reached are
// Planned, in the script's order, apart from those reached; a replayed
// call without a name takes the script's. Once a phase is reached it
// leaves Planned for Phases.
func TestPlannedPhases(t *testing.T) {
	l, id, folder, session := fakeRun(t, launchedLine+startA+startB, "")
	testcheck.Write(t, filepath.Join(session, "workflows", "scripts", "sweep-wf_abc.js"), `export const meta = {
  name: 'sweep', description: 'Look at each part',
  phases: [{ title: 'Map', detail: 'two' }, { title: 'Review' }, { title: 'Verify', detail: 'last' }],
}
`)
	w := model.Workflow{RunID: "wf_abc", TaskID: "t1"}
	got, err := l.ReadWorkflow(id, folder, w)
	testcheck.NoErr(t, err)
	if got.Name != "sweep" || got.Description != "Look at each part" || len(got.Phases) != 1 || got.Phases[0].Title != "Map" ||
		!reflect.DeepEqual(got.Planned, []model.WorkflowPhase{{Title: "Review"}, {Title: "Verify", Detail: "last"}}) || got.Started.IsZero() {
		t.Fatalf("got %+v", got)
	}
	f, err := os.OpenFile(filepath.Join(session, "subagents", "workflows", "wf_abc", "journal.jsonl"), os.O_APPEND|os.O_WRONLY, 0)
	testcheck.NoErr(t, err)
	_, _ = f.WriteString(`{"type":"started","key":"k3","agentId":"a3","label":"review:a","phase":"Review"}` + "\n")
	_ = f.Close()
	got, _ = l.ReadWorkflow(id, folder, w)
	if len(got.Phases) != 2 || got.Phases[1].Title != "Review" || len(got.Planned) != 1 || got.Planned[0].Title != "Verify" ||
		got.RunningPhases[2] != 1 {
		t.Errorf("after Review started: %+v", got)
	}
}

// A script without a meta, or with one that's code, plans nothing; the
// run reads as before.
func TestNoPlan(t *testing.T) {
	l, id, folder, session := fakeRun(t, launchedLine+startA, "")
	testcheck.Write(t, filepath.Join(session, "workflows", "scripts", "x-wf_abc.js"), "export const meta = { phases: steps() }\n")
	got, err := l.ReadWorkflow(id, folder, model.Workflow{RunID: "wf_abc", TaskID: "t1"})
	testcheck.NoErr(t, err)
	if len(got.Planned) != 0 || len(got.Phases) != 1 || got.Started.IsZero() {
		t.Errorf("got %+v", got)
	}
}

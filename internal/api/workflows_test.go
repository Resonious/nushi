package api

import (
	"errors"
	"fmt"
	"testing"
	"time"

	"connectrpc.com/connect"

	"github.com/afrase/nushi/internal/features/chats"
	"github.com/afrase/nushi/internal/model"
)

// A workflow goes out field for field, its times in Unix milliseconds and
// those not known as 0; the status says how many run and an own turn.
func TestWorkflowProto(t *testing.T) {
	start := time.UnixMilli(1794798436066)
	w := model.Workflow{RunID: "wf_1", TaskID: "t1", Name: "n", Description: "d", State: "done", End: "completed", Started: start,
		Phases: []model.WorkflowPhase{{Title: "Map", Detail: "x", Started: 2, Done: 1, Failed: 1}}, Agents: 2, Done: 1, Failed: 1,
		Running: []string{"a"}, RunningCount: 1, Summary: "s", Stalled: true, Planned: []model.WorkflowPhase{{Title: "Verify", Detail: "y"}}}
	it := itemProto(&model.Item{ID: "c", Kind: model.ToolCall, Workflow: &w}, false)
	p := it.Workflow
	if p.RunId != "wf_1" || p.Name != "n" || p.Description != "d" || p.State != "done" || p.End != "completed" ||
		p.Started != 1794798436066 || p.Ended != 0 || p.Active != 0 || len(p.Phases) != 1 || p.Phases[0].Failed != 1 || p.Agents != 2 ||
		p.Done != 1 || p.Failed != 1 || len(p.Running) != 1 || p.RunningCount != 1 || p.Summary != "s" || !p.Stalled ||
		len(p.Planned) != 1 || p.Planned[0].Title != "Verify" || p.Planned[0].Detail != "y" {
		t.Errorf("got %+v", p)
	}
	if itemProto(&model.Item{ID: "c"}, false).Workflow != nil {
		t.Error("a workflow on a plain item")
	}
	if itemProto(&model.Item{ID: "c", Workflow: &model.Workflow{RunID: "wf_1", TaskID: "t1"}}, false).Workflow != nil {
		t.Error("a run not followed: no workflow, as the proto says")
	}
	a := workflowAgentProto(model.WorkflowAgent{ID: "a1", Label: "l", Phase: "p", State: "done", Model: "m", Started: start, Tokens: 1 << 40, ToolCalls: 3, Prompt: "q", Result: "r"})
	if a.Id != "a1" || a.Started != 1794798436066 || a.Ended != 0 || a.Tokens != 1<<31-1 || a.ToolCalls != 3 || a.Prompt != "q" || a.Result != "r" {
		t.Errorf("agent %+v", a)
	}
	st := statusProto(model.Status{Background: 3, Workflows: 1, OwnTurn: true})
	if st.Background != 3 || st.Workflows != 1 || !st.OwnTurn {
		t.Errorf("status %+v", st)
	}
}

// No such workflow (a chat, call or agent not there, a run's files gone)
// is NotFound; anything else is a refusal.
func TestWorkflowErr(t *testing.T) {
	if code := connect.CodeOf(workflowErr(fmt.Errorf("the run's files: %w", chats.ErrNoWorkflow))); code != connect.CodeNotFound {
		t.Errorf("no workflow: %v", code)
	}
	if code := connect.CodeOf(workflowErr(errors.New("permission denied"))); code == connect.CodeNotFound {
		t.Errorf("a read that failed: %v", code)
	}
}

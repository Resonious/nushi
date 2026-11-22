package e2e

import (
	"context"
	"strings"
	"testing"

	"connectrpc.com/connect"

	"github.com/afrase/nushi/internal/acptest"
	nushiv1 "github.com/afrase/nushi/internal/gen/nushi/v1"
)

// An Antigravity chat, on the fake shaped like agy 1.5.12: listed last,
// with its resume command; config options (model, thought_level, mode) and
// commands arrive on start; its question's Other is "<id>_other"; its
// permissions carry allow/deny; a show call strips "Run " on the tool row
// and preserves the path input on its permission card; changing model
// updates thought_level; and Delete leaves history alone (no session/delete).
func TestAnAgyChat(t *testing.T) {
	ctx := context.Background()
	history := &acptest.History{}
	d := startDaemon(t, t.TempDir(), history)
	a := open(t, d)
	agents := must(a.c.ListAgents(ctx, connect.NewRequest(&nushiv1.ListAgentsRequest{}))).Agents
	if ag := agents[8]; agents[7].Name != "pig" || ag.Name != "agy" || ag.Title != "Antigravity" || ag.Resume != "agy --conversation" || ag.DeleteArchives || ag.Mcp {
		t.Fatalf("agents = %v", agents)
	}
	start := must(a.c.StartChat(ctx, connect.NewRequest(&nushiv1.StartChatRequest{Agent: "agy", Folder: t.TempDir()})))
	id := start.ChatId
	if got := config(a.get(id).Config); got != "model/model=gemini-4-neon thought_level/thought_level=high mode/mode=default" {
		t.Errorf("options = %s", got)
	}
	if got := a.commandNames(id); got != "compact plan goal" {
		t.Errorf("commands = %q, want compact plan goal", got)
	}
	if st := a.get(id).Status; st.CanFork || st.CanRewind || st.CanAskContext {
		t.Errorf("status = %v, want no fork, rewind or context", st)
	}

	// Question with q1_other free-text field.
	a.send(id, "a question")
	q := a.waitFor("the question", questionPending).GetItem().Item
	if len(q.Fields) != 2 || q.Fields[0].Id != "q1" || len(q.Fields[0].Options) != 2 || q.Fields[1].Id != "q1_other" || q.Fields[1].OtherFor != "q1" {
		t.Fatalf("question fields %v", q.Fields)
	}
	must(a.c.AnswerQuestion(ctx, connect.NewRequest(&nushiv1.AnswerQuestionRequest{
		ChatId:  id,
		ItemId:  q.Id,
		Answers: []*nushiv1.FieldAnswer{{FieldId: "q1_other", Values: []string{"Green"}}},
	})))
	a.waitFor("the answer", turnEnded(id))
	if last := lastItem(a.get(id)); last.Text != `Answer: {"action":"accept","content":{"q1_other":"Green"}}` {
		t.Errorf("agy got %q", last.Text)
	}

	// Client MCP show tool: "Run " stripped on the tool call row, and input
	// preserved on the permission card so the app names the file.
	a.send(id, "show preview")
	perm := a.waitFor("the show permission prompt", pendingPermission).GetItem().Item
	if !strings.Contains(perm.Input, "hello.txt") {
		t.Errorf("show permission input = %q, want hello.txt", perm.Input)
	}
	must(a.c.AnswerPermission(ctx, connect.NewRequest(&nushiv1.AnswerPermissionRequest{ChatId: id, ItemId: perm.Id, OptionId: "allow"})))
	a.waitFor("show turn end", turnEnded(id))
	var sawShow bool
	for _, it := range a.get(id).Items {
		if it.Kind == nushiv1.ItemKind_ITEM_KIND_TOOL_CALL && it.Title == "mcp_nushi_show" {
			sawShow = true
		}
	}
	if !sawShow {
		t.Errorf("tool call title wasn't normalized to mcp_nushi_show: %v", a.get(id).Items)
	}

	// Permission allow and deny.
	for _, pick := range []string{"allow", "deny"} {
		a.send(id, "ask permission")
		p := a.waitFor("the permission prompt", pendingPermission).GetItem().Item
		var opts []string
		for _, o := range p.Options {
			opts = append(opts, o.Id+"/"+o.Kind)
		}
		if got := strings.Join(opts, " "); got != "allow/allow_once deny/reject_once" {
			t.Errorf("permission options = %s", got)
		}
		must(a.c.AnswerPermission(ctx, connect.NewRequest(&nushiv1.AnswerPermissionRequest{ChatId: id, ItemId: p.Id, OptionId: pick})))
		ended := a.waitFor("the turn's end", turnEnded(id)).GetStatus().GetEnded()
		wantEnd := nushiv1.TurnEnd_TURN_END_DONE
		if pick == "deny" {
			wantEnd = nushiv1.TurnEnd_TURN_END_STOPPED
		}
		if ended != wantEnd {
			t.Errorf("after %s ended %v, want %v", pick, ended, wantEnd)
		}
	}

	// Switching model narrows thought_level options and updates config.
	must(a.c.SetConfigOption(ctx, connect.NewRequest(&nushiv1.SetConfigOptionRequest{ChatId: id, ConfigId: "thought_level", Value: "xhigh"})))
	must(a.c.SetConfigOption(ctx, connect.NewRequest(&nushiv1.SetConfigOptionRequest{ChatId: id, ConfigId: "model", Value: "gemini-3.8-flash"})))
	if got := config(a.get(id).Config); got != "model/model=gemini-3.8-flash thought_level/thought_level=high mode/mode=default" {
		t.Errorf("after model switch: %s", got)
	}

	// Delete: agy has no session/delete, so plan reports DeletesHistory=false.
	plan := must(a.c.PlanDeleteChat(ctx, connect.NewRequest(&nushiv1.PlanDeleteChatRequest{ChatId: id})))
	if plan.DeletesHistory {
		t.Errorf("plan.DeletesHistory = true, want false")
	}
	must(a.c.DeleteChat(ctx, connect.NewRequest(&nushiv1.DeleteChatRequest{ChatId: id})))
}

package acptest

import (
	"encoding/json"
	"strings"
)

// Agy makes an Agent answer as Antigravity CLI 1.5.12 (`agy acp`) does
// where Nushi's features follow it (docs/facts/agy.md): it names itself
// "fake-agy"; initialize advertises load, list, resume, close and
// additionalDirectories (no fork or delete); a session has config options
// "model", "thought_level" (narrowed by model) and "mode" (default,
// accept-edits, auto, plan), kept with the session; setting one answers
// with configOptions and sends config_option_update; opening a session
// sends available_commands_update and usage_update; the prompt "question"
// asks via ask_question with "<id>_other"; the prompt "permission" asks
// with "allow" and "deny"; and the prompt "show" calls "Run mcp_nushi_show"
// asking permission with its path input.

func agyInit() map[string]any {
	none := map[string]any{}
	return map[string]any{
		"protocolVersion": 1,
		"agentInfo":       map[string]any{"name": "fake-agy", "version": "1.5.12"},
		"agentCapabilities": map[string]any{
			"loadSession":        true,
			"promptCapabilities": map[string]any{"image": true, "audio": false, "embeddedContext": true},
			"sessionCapabilities": map[string]any{
				"additionalDirectories": none,
				"close":                 none,
				"list":                  none,
				"load":                  none,
				"resume":                none,
			},
		},
	}
}

var agyCommands = map[string]any{
	"sessionUpdate": "available_commands_update",
	"availableCommands": []map[string]any{
		{"name": "compact", "description": "Compact the conversation now"},
		{"name": "plan", "description": "Plan carefully before executing a task."},
		{"name": "goal", "description": "Run until the specified goal is completely finished."},
	},
}

// agyAnswer answers a request with agy's result where it isn't the plain
// agent's, which is result; opened is the session the request opened, if
// it did (session/new or session/load).
func (a *Agent) agyAnswer(f frame, opened string, result any) {
	var set struct{ SessionID, ConfigID, Value string }
	_ = json.Unmarshal(f.Params, &set)
	switch f.Method {
	case "initialize":
		result = agyInit()
	case "session/fork", "session/delete":
		a.send(frame{ID: f.ID, Error: &rpcError{Code: -32601, Message: "Method not found: " + f.Method}})
		return
	case "session/new":
		result = map[string]any{"sessionId": opened, "configOptions": a.History.agyOptions(opened, "", "")}
	case "session/load":
		result = map[string]any{"sessionId": opened, "configOptions": a.History.agyOptions(opened, "", "")}
	case "session/set_config_option":
		opts := a.History.agyOptions(set.SessionID, set.ConfigID, set.Value)
		result = map[string]any{"configOptions": opts}
		r, _ := json.Marshal(result)
		a.send(frame{ID: f.ID, Result: r})
		a.live(set.SessionID, map[string]any{"sessionUpdate": "config_option_update", "configOptions": opts})
		return
	}
	r, _ := json.Marshal(result)
	a.send(frame{ID: f.ID, Result: r})
	if opened != "" {
		a.live(opened, agyCommands)
		a.live(opened, map[string]any{"sessionUpdate": "usage_update", "used": 0, "size": 1048576})
	}
}

// agyScript plays the prompts agy has its own script for, and returns the
// turn's stop reason, or "" for the plain agent's script.
func (a *Agent) agyScript(session, text string) string {
	if !a.Agy {
		return ""
	}
	switch {
	case strings.Contains(text, "question"):
		return a.agyQuestion(session)
	case strings.Contains(text, "show"):
		return a.agyShow(session)
	case strings.Contains(text, "permission"):
		return a.agyPermission(session)
	}
	return ""
}

// agyOptions is session's config options as agy 1.5.12 answers them, option
// id first set to value if one is named. Switching to gemini-3.8-flash drops
// xhigh from thought_level, as observed on agy 1.5.12.
func (h *History) agyOptions(session, id, value string) []map[string]any {
	h.mu.Lock()
	defer h.mu.Unlock()
	cur := h.options[session]
	if cur == nil {
		cur = map[string]string{"model": "gemini-4-neon", "thought_level": "high", "mode": "default"}
	}
	if id != "" {
		cur[id] = value
		if id == "model" && value == "gemini-3.8-flash" && cur["thought_level"] == "xhigh" {
			cur["thought_level"] = "high"
		}
		if h.options == nil {
			h.options = map[string]map[string]string{}
		}
		h.options[session] = cur
	}
	option := func(id, name, category string, choices ...map[string]any) map[string]any {
		return map[string]any{"id": id, "name": name, "category": category, "type": "select", "currentValue": cur[id], "options": choices}
	}
	levels := []map[string]any{
		{"value": "low", "name": "Low"},
		{"value": "medium", "name": "Medium"},
		{"value": "high", "name": "High"},
	}
	if cur["model"] == "gemini-4-neon" {
		levels = append(levels, map[string]any{"value": "xhigh", "name": "Extra"})
	}
	return []map[string]any{
		option("model", "Model", "model",
			map[string]any{"value": "gemini-4-neon", "name": "Gemini 4 Neon"},
			map[string]any{"value": "gemini-3.8-flash", "name": "Gemini 3.8 Flash"}),
		option("thought_level", "Thinking Level", "thought_level", levels...),
		option("mode", "Mode", "mode",
			map[string]any{"value": "default", "name": "Default", "description": "Ask before edits and commands, per your permission settings."},
			map[string]any{"value": "accept-edits", "name": "Accept edits", "description": "Approve file edits in the workspace without asking."},
			map[string]any{"value": "auto", "name": "Auto", "description": "Approve edits and safe commands; ask before irreversible actions."},
			map[string]any{"value": "plan", "name": "Plan", "description": "Plan carefully before executing a task."}),
	}
}

// agyAsk asks permission for a tool call on session, with agy's allow/deny
// options, and returns the outcome and the option picked.
func (a *Agent) agyAsk(session string, call map[string]any) (outcome, option string) {
	res := a.request("session/request_permission", map[string]any{
		"sessionId": session,
		"toolCall":  call,
		"options": []map[string]any{
			{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
			{"optionId": "deny", "name": "Deny", "kind": "reject_once"},
		},
	})
	var r struct {
		Outcome struct{ Outcome, OptionID string } `json:"outcome"`
	}
	_ = json.Unmarshal(res, &r)
	return r.Outcome.Outcome, r.Outcome.OptionID
}

func (a *Agent) agyPermission(session string) string {
	id := "call_agy_cmd"
	call := map[string]any{
		"toolCallId": id, "name": "run_command", "title": "echo done", "kind": "execute", "status": "pending",
		"rawInput": map[string]any{"CommandLine": "echo done"},
	}
	a.update(session, map[string]any{
		"sessionUpdate": "tool_call", "toolCallId": id, "name": "run_command", "title": "echo done", "kind": "execute", "status": "pending",
		"rawInput": map[string]any{"CommandLine": "echo done"},
	})
	outcome, option := a.agyAsk(session, call)
	if outcome != "selected" || option == "deny" {
		a.update(session, map[string]any{"sessionUpdate": "tool_call_update", "toolCallId": id, "status": "failed"})
		return "cancelled"
	}
	a.update(session, map[string]any{"sessionUpdate": "tool_call_update", "toolCallId": id, "status": "completed",
		"content": []map[string]any{{"type": "content", "content": map[string]any{"type": "text", "text": "done\n"}}}})
	a.say(session, "Permission: "+outcome+" "+option)
	return "end_turn"
}

func (a *Agent) agyShow(session string) string {
	id := "call_agy_show"
	input := map[string]any{"path": "hello.txt"}
	call := map[string]any{
		"toolCallId": id, "name": "mcp_nushi_show", "title": "Run mcp_nushi_show", "kind": "other", "status": "pending",
		"rawInput": input,
	}
	a.update(session, map[string]any{
		"sessionUpdate": "tool_call", "toolCallId": id, "name": "mcp_nushi_show", "title": "Run mcp_nushi_show", "kind": "other", "status": "pending",
		"rawInput": input,
	})
	outcome, option := a.agyAsk(session, call)
	if outcome != "selected" || option == "deny" {
		a.update(session, map[string]any{"sessionUpdate": "tool_call_update", "toolCallId": id, "status": "failed"})
		return "cancelled"
	}
	a.update(session, map[string]any{"sessionUpdate": "tool_call_update", "toolCallId": id, "status": "completed"})
	a.say(session, "Shown hello.txt.")
	return "end_turn"
}

func (a *Agent) agyQuestion(session string) string {
	id := "call_agy_q"
	a.update(session, map[string]any{
		"sessionUpdate": "tool_call", "toolCallId": id, "name": "ask_question", "title": "Run ask_question", "kind": "other", "status": "pending",
	})
	res := a.request("elicitation/create", map[string]any{
		"sessionId": session, "toolCallId": id, "mode": "form", "message": "The agent has a question.",
		"requestedSchema": map[string]any{
			"type": "object",
			"properties": map[string]any{
				"q1": map[string]any{
					"type": "string", "title": "Please pick Red or Blue:",
					"oneOf": []map[string]any{
						{"const": "1", "title": "(Recommended) Red"},
						{"const": "2", "title": "Blue"},
					},
				},
				"q1_other": map[string]any{
					"type": "string", "title": "Other", "description": "Optional free-form answer to: Please pick Red or Blue:",
				},
			},
		},
	})
	var r struct{ Action string }
	_ = json.Unmarshal(res, &r)
	if r.Action != "accept" {
		a.update(session, map[string]any{"sessionUpdate": "tool_call_update", "toolCallId": id, "status": "failed"})
		return "cancelled"
	}
	a.update(session, map[string]any{"sessionUpdate": "tool_call_update", "toolCallId": id, "status": "completed"})
	a.say(session, "Answer: "+strings.TrimSpace(string(res)))
	return "end_turn"
}

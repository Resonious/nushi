package claude

import (
	"encoding/json"
	"math"
	"time"

	"github.com/afrase/nushi/internal/model"
)

// UsageModel is the model a usage_update names: claude-acp-go sends it
// under _claude/model with each one.
func (Harness) UsageModel(meta map[string]any) string {
	m, _ := meta["_claude/model"].(string)
	return m
}

// Limits reads the account's rate limit a usage_update carries:
// claude-acp-go passes claude's rate_limit_event on as
// _claude/rateLimit, claude's rate_limit_info as it wrote it ({status,
// resetsAt, rateLimitType, utilization, overage…}). It's read leniently, as
// claude adds to it: a field of another type or missing is left out, the
// rest kept; with no status it's none.
func (Harness) Limits(meta map[string]any) []model.Limit {
	v, ok := meta["_claude/rateLimit"]
	if !ok {
		return nil
	}
	// A map off the wire, or json.RawMessage when the agent runs in the
	// same process.
	b, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	var info map[string]any
	if json.Unmarshal(b, &info) != nil {
		return nil
	}
	status, _ := info["status"].(string)
	if status == "" {
		return nil
	}
	l := model.Limit{Status: status}
	l.Kind, _ = info["rateLimitType"].(string)
	if u, ok := info["utilization"].(float64); ok {
		l.Utilization = &u
	}
	if at, ok := info["resetsAt"].(float64); ok && at > 0 {
		l.ResetsAt = epoch(at)
	}
	return []model.Limit{l}
}

// epoch is a time claude wrote as seconds since the epoch (the SDK's
// resetsAt), or in ms should it ever be: no reset is past the year 5000 in
// seconds.
func epoch(n float64) time.Time {
	if n > 1e11 {
		return time.UnixMilli(int64(n))
	}
	sec, frac := math.Modf(n)
	return time.Unix(int64(sec), int64(frac*1e9))
}

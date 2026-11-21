package claude

import (
	"encoding/json"
	"reflect"
	"testing"
	"time"

	"github.com/afrase/nushi/internal/model"
)

// Claude's rate limit is read however it came, and leniently: what claude
// adds is ignored, a field of another type left out; without a status
// there's none.
func TestLimits(t *testing.T) {
	used := 0.9
	for _, tc := range []struct {
		name string
		v    any
		want []model.Limit
	}{
		{"the SDK's example, off the wire", map[string]any{"resetsAt": 1700000000.0, "status": "allowed_warning", "utilization": 0.9},
			[]model.Limit{{Status: "allowed_warning", Utilization: &used, ResetsAt: time.Unix(1700000000, 0)}}},
		{"in-process, with more than Nushi reads", json.RawMessage(`{"status":"allowed","rateLimitType":"five_hour","overageStatus":"rejected","isUsingOverage":false,"surpassedThreshold":0.5}`),
			[]model.Limit{{Status: "allowed", Kind: "five_hour"}}},
		{"a field of another type", map[string]any{"status": "rejected", "utilization": "90%", "resetsAt": "soon", "rateLimitType": 7},
			[]model.Limit{{Status: "rejected"}}},
		{"no status", map[string]any{"utilization": 0.5}, nil},
		{"not an object", "allowed", nil},
	} {
		if got := (Harness{}).Limits(map[string]any{"_claude/rateLimit": tc.v}); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: %+v", tc.name, got)
		}
	}
	if got := (Harness{}).Limits(map[string]any{"_claude/model": "claude-opus-5-5"}); got != nil {
		t.Errorf("no rate limit: %+v", got)
	}
	if got := (Harness{}).UsageModel(map[string]any{"_claude/model": "claude-opus-5-5"}); got != "claude-opus-5-5" {
		t.Errorf("model %q", got)
	}
}

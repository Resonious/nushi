package model

import "time"

// UsageEnd says how a turn's usage came to be recorded (ADR 0136).
type UsageEnd string

const (
	// UsageTurn is a turn of the user's that ended with the prompt's answer.
	UsageTurn UsageEnd = "turn"
	// UsageReleased is a turn of the user's whose work ended while the
	// agent held its prompt for background subagents (Transcript.TurnDone):
	// its cost so far, the tokens coming with UsageHeld.
	UsageReleased UsageEnd = "released"
	// UsageHeld is the late answer to a held prompt: its tokens. It
	// continues a UsageReleased turn and isn't counted as a turn of its own.
	UsageHeld UsageEnd = "held"
	// UsageOwn is the agent's own turn, after a background task: no prompt
	// answered it, so only its cost is known.
	UsageOwn UsageEnd = "own"
)

// TurnUsage is what one of a chat's turns used, as the chat saw it: the
// prompt's tokens, and the session's cost so far as the agent last said
// it (cumulative; features/usage makes the turn's own of it).
type TurnUsage struct {
	At   time.Time // when the turn ended
	Chat string    // the stored chat's id: a side chat's is its chat's
	// Meter is the chat whose session Total is the running total of: the
	// chat's own id, a side chat's own for a side chat.
	Meter string
	// From is the chat a fork's session forked from, whose total the
	// fork's first figure may still carry; "" for none.
	From string
	// Began is when the chat began (its record's Created): a chat older
	// than the usage kept has spent what its first figure says before.
	Began                                time.Time
	Side                                 bool // a side chat's turn, counted toward Chat
	Agent, Model, Folder                 string
	End                                  UsageEnd
	Input, Output, CacheRead, CacheWrite int64
	// Total is the session's cost so far, as the agent last reported it,
	// in Currency; Costed says the agent has reported one at all.
	Total    float64
	Currency string
	Costed   bool
}

// UsageRow is a turn as kept: as TurnUsage, with the turn's own cost.
type UsageRow struct {
	At                                   time.Time
	Chat                                 string
	Side                                 bool
	Agent, Model, Folder                 string
	End                                  UsageEnd
	Input, Output, CacheRead, CacheWrite int64
	Cost                                 float64 // this turn's: Total less the last figure measured
	Currency                             string
	Costed                               bool
	// Total is the session's total Cost was measured against, for the next
	// figure after a daemon restart.
	Total float64
}

// Limit is an account limit an agent reported of itself (Claude's rate
// limits): Nushi never asks a service for it (ADR 0136).
type Limit struct {
	Agent string
	// Kind is the limit's window as the agent names it ("five_hour",
	// "seven_day"); "" when it doesn't say.
	Kind string
	// Status is the agent's word on it: "allowed", "allowed_warning",
	// "rejected".
	Status string
	// Utilization is how much of it is used, 0 to 1; nil when not said.
	Utilization *float64
	ResetsAt    time.Time // zero when not said
	Seen        time.Time // when the agent reported it
}

// UsageTotals sums turns: their cost by currency, their tokens, and how
// many turns they were.
type UsageTotals struct {
	Cost                                 map[string]float64
	Input, Output, CacheRead, CacheWrite int64
	Turns                                int64
}

// UsageGroup is the totals of the turns that share Key: a day
// (YYYY-MM-DD), an agent, a model or a project folder.
type UsageGroup struct {
	Key string
	UsageTotals
}

// UsageChat is a chat's totals; Title is "" when the chat is gone.
type UsageChat struct {
	ID, Title, Agent string
	UsageTotals
}

// UsageReport is what was used in a span of time (GetUsage).
type UsageReport struct {
	Totals                        UsageTotals
	Days, Agents, Models, Folders []UsageGroup
	Chats                         []UsageChat // the costliest, most first
	NoCost                        []string    // agents whose turns reported no cost
	Earliest                      time.Time   // the first turn kept, of all; zero for none
	Limits                        []Limit
}

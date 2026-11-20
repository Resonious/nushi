package api

import (
	"log/slog"

	nushiv1 "github.com/afrase/nushi/internal/gen/nushi/v1"
)

// CodexGoPref keeps whether Codex's chats run through Nushi's Go agent
// rather than the codex-acp adapter (internal/store; ADR 0142). The
// agents feature reads it each time a Codex chat's agent starts, so a
// change needs no restart.
type CodexGoPref interface {
	CodexGoAgent() bool
	SetCodexGoAgent(on bool) error
}

// setCodexGo sets what SetSettings gives of it, when given and changed.
func (s *server) setCodexGo(set *nushiv1.Settings) error {
	if s.CodexGo == nil || set.CodexGoAgent == nil || *set.CodexGoAgent == s.CodexGo.CodexGoAgent() {
		return nil
	}
	if err := s.CodexGo.SetCodexGoAgent(*set.CodexGoAgent); err != nil {
		return err
	}
	slog.Info("codex's agent", "go", *set.CodexGoAgent)
	return nil
}

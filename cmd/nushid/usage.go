package main

import (
	"log/slog"

	"github.com/afrase/nushi/internal/database"
	"github.com/afrase/nushi/internal/features/usage"
	"github.com/afrase/nushi/internal/store"
)

// openUsage keeps usage in the database at path (ADR 0136), and returns
// what closes them both, usage first. A database that won't open is
// logged and the daemon goes on without usage: chats never depend on it.
func openUsage(path string, st *store.Store) (*usage.Service, func()) {
	db, err := database.Open(path)
	if err != nil {
		slog.Error("usage isn't kept: opening the database", "err", err)
		u := usage.New(nil, st)
		return u, u.Close
	}
	u := usage.New(db, st)
	return u, func() {
		u.Close()
		if err := db.Close(); err != nil {
			slog.Warn("closing the database", "err", err)
		}
	}
}

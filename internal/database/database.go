// Package database is the daemon's SQLite database: one file in the data
// folder, through modernc.org/sqlite (pure Go, so Linux's and Windows's
// builds stay without cgo; ADR 0136). Settings and chats' records stay
// JSON files (internal/store); what is better asked than read whole, such
// as each turn's usage, is kept here.
package database

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"time"

	_ "modernc.org/sqlite" // the "sqlite" driver
)

// DB is the open database.
type DB struct {
	db    *sql.DB
	began time.Time // when it was made (began)
}

// busyTimeout is how long a write waits for another's lock before failing.
const busyTimeout = 5 * time.Second

// Open opens the database at path, making it (only the user may read it)
// and bringing its tables up to date as needed.
func Open(path string) (*DB, error) {
	// The file first, so it is the user's alone: SQLite gives its WAL
	// files the same permissions.
	if err := registerDay(); err != nil {
		return nil, fmt.Errorf("opening the database: %w", err)
	}
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o600) //nolint:gosec // the data folder's, main's choice

	if err != nil {
		return nil, fmt.Errorf("making the database: %w", err)
	}
	_ = f.Close()
	q := url.Values{}
	for _, p := range []string{"journal_mode(WAL)", "synchronous(NORMAL)", "busy_timeout(" + strconv.Itoa(int(busyTimeout.Milliseconds())) + ")", "foreign_keys(ON)"} {
		q.Add("_pragma", p)
	}
	q.Set("_txlock", "immediate")                      // a write takes the lock as it begins, so two never deadlock upgrading
	db, err := sql.Open("sqlite", path+"?"+q.Encode()) // a plain path, Windows's too; the driver reads the query

	if err != nil {
		return nil, fmt.Errorf("opening the database: %w", err)
	}
	d := &DB{db: db}
	if err := d.migrate(context.Background()); err != nil {
		_ = db.Close()
		return nil, err
	}
	var began int64
	if err := db.QueryRowContext(context.Background(), `SELECT value FROM meta WHERE key = 'began'`).Scan(&began); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("reading the database: %w", err)
	}
	d.began = time.UnixMilli(began)
	return d, nil
}

// Close closes the database.
func (d *DB) Close() error { return d.db.Close() }

// Began is when the database was made: usage before it wasn't kept.
func (d *DB) Began() time.Time { return d.began }

// migrations make the tables, one step per version (PRAGMA user_version):
// a later feature adds its own at the end, and never changes one that
// shipped.
var migrations = []string{
	// 1: what each turn used, account limits, and when the database began.
	`CREATE TABLE meta (key TEXT PRIMARY KEY, value ANY NOT NULL) STRICT;
	INSERT INTO meta (key, value) VALUES ('began', CAST(unixepoch('subsec') * 1000 AS INTEGER));
	CREATE TABLE turns (
		id          INTEGER PRIMARY KEY,
		at          INTEGER NOT NULL,           -- when the turn ended, ms since the epoch
		chat        TEXT NOT NULL,              -- the stored chat's id (a side chat's chat's)
		side        INTEGER NOT NULL DEFAULT 0, -- a side chat's turn
		agent       TEXT NOT NULL,
		model       TEXT NOT NULL DEFAULT '',
		folder      TEXT NOT NULL DEFAULT '',   -- the project's folder: a worktree's repository's
		ending      TEXT NOT NULL,              -- model.UsageEnd
		input       INTEGER NOT NULL DEFAULT 0,
		output      INTEGER NOT NULL DEFAULT 0,
		cache_read  INTEGER NOT NULL DEFAULT 0,
		cache_write INTEGER NOT NULL DEFAULT 0,
		cost        REAL NOT NULL DEFAULT 0,    -- the turn's own
		currency    TEXT NOT NULL DEFAULT '',
		costed      INTEGER NOT NULL DEFAULT 0, -- the agent reports a cost
		total       REAL NOT NULL DEFAULT 0     -- the session's total cost was measured against
	) STRICT;
	CREATE INDEX turns_at ON turns (at);
	CREATE INDEX turns_chat ON turns (chat, side, id);
	CREATE TABLE limits (
		agent       TEXT NOT NULL,
		kind        TEXT NOT NULL,
		status      TEXT NOT NULL,
		utilization REAL,
		resets_at   INTEGER,                    -- ms since the epoch
		seen        INTEGER NOT NULL,
		PRIMARY KEY (agent, kind)
	) STRICT;`,
}

// migrate brings the tables to the latest version, in one transaction.
func (d *DB) migrate(ctx context.Context) error {
	tx, err := d.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("opening the database: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	var v int
	if err := tx.QueryRowContext(ctx, `PRAGMA user_version`).Scan(&v); err != nil {
		return fmt.Errorf("reading the database's version: %w", err)
	}
	if v > len(migrations) {
		return fmt.Errorf("the database is version %d, newer than this daemon's %d", v, len(migrations))
	}
	if v == len(migrations) {
		return nil
	}
	for i := v; i < len(migrations); i++ {
		if _, err := tx.ExecContext(ctx, migrations[i]); err != nil {
			return fmt.Errorf("updating the database to version %d: %w", i+1, err)
		}
	}
	// PRAGMA takes no parameter; the number is ours.
	if _, err := tx.ExecContext(ctx, `PRAGMA user_version = `+strconv.Itoa(len(migrations))); err != nil {
		return fmt.Errorf("updating the database's version: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("updating the database: %w", err)
	}
	return nil
}

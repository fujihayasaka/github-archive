package storage

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"fmt"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/interfaces"

	"github.com/github/github-telemetry-go/kvp"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

// GetMostRecentDependabotEventReadiness retrieves aggregate readiness counts for the most recent event.
// Returns nil (with no error) if no event is found.
func (r *MySQLSnapshotsAdapter) GetMostRecentDependabotEventReadiness(ctx context.Context, repositoryID uint64, opts ...interfaces.EventQueryOption) (*interfaces.DependabotEvent, error) {
	options := interfaces.ApplyEventQueryOptions(opts...)

	eventTypeStr := ""
	if options.EventType != nil {
		eventTypeStr = string(*options.EventType)
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "GetMostRecentDependabotEventReadiness", "GetMostRecentDependabotEventReadiness",
		kvp.Int64("gh.repo.id", int64(repositoryID)),
		kvp.String("event_type", eventTypeStr),
	)
	defer ender()

	eventRow, found, err := r.findMostRecentEvent(ctx, repositoryID, options)
	if err != nil {
		return nil, err
	}

	if !found {
		return nil, nil
	}

	return r.aggregateReadiness(ctx, eventRow)
}

// GetDependabotEventReadinessByID retrieves aggregate readiness counts for an event by its primary key.
// Returns nil (with no error) if the event is not found.
func (r *MySQLSnapshotsAdapter) GetDependabotEventReadinessByID(ctx context.Context, eventID uint64) (*interfaces.DependabotEvent, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "GetDependabotEventReadinessByID", "GetDependabotEventReadinessByID",
		kvp.Uint64("event_id", eventID),
	)
	defer ender()

	eventRow, found, err := r.findEventByID(ctx, eventID)
	if err != nil {
		return nil, err
	}

	if !found {
		return nil, nil
	}

	return r.aggregateReadiness(ctx, eventRow)
}

func (r *MySQLSnapshotsAdapter) aggregateReadiness(ctx context.Context, eventRow *eventModel) (*interfaces.DependabotEvent, error) {
	event := &interfaces.DependabotEvent{
		ID:        eventRow.ID,
		EventType: interfaces.EventType(eventRow.EventType),
		Ref:       eventRow.Ref,
		SHA:       eventRow.SHA,
		CreatedAt: eventRow.CreatedAt,
	}
	_, err := QueryRow(ctx, r.DB, &event.Readiness, "AggregateEventReadiness",
		"SELECT COUNT(*) AS total, COUNT(snapshot_id) AS received, COUNT(CASE WHEN snapshot_id IS NULL AND deadline < NOW() THEN 1 END) AS expired FROM ds_dependabot_requested_snapshots WHERE event_id = ?",
		eventRow.ID,
	)
	if err != nil {
		return nil, err
	}

	return event, nil
}

type eventModel struct {
	ID        uint64    `db:"id"`
	EventType string    `db:"event_type"`
	Ref       string    `db:"ref"`
	SHA       string    `db:"sha"`
	CreatedAt time.Time `db:"created_at"`
}

func (r *MySQLSnapshotsAdapter) findEventByID(ctx context.Context, eventID uint64) (*eventModel, bool, error) {
	dest := &eventModel{}
	found, err := QueryRow(ctx, r.DB, dest, "FindEventByID",
		"SELECT id, event_type, ref, sha, created_at FROM ds_dependabot_events WHERE id = ?",
		eventID,
	)
	if err != nil {
		return nil, false, err
	}

	return dest, found, nil
}

func (r *MySQLSnapshotsAdapter) findMostRecentEvent(ctx context.Context, repositoryID uint64, options interfaces.EventQueryOptions) (*eventModel, bool, error) {
	dest := &eventModel{}
	var found bool
	var err error

	if options.EventType != nil {
		found, err = QueryRow(ctx, r.DB, dest, "FindMostRecentEventByType",
			"SELECT id, event_type, ref, sha, created_at FROM ds_dependabot_events WHERE repository_id = ? AND event_type = ? ORDER BY id DESC LIMIT 1",
			repositoryID, string(*options.EventType),
		)
	} else {
		found, err = QueryRow(ctx, r.DB, dest, "FindMostRecentEvent",
			"SELECT id, event_type, ref, sha, created_at FROM ds_dependabot_events WHERE repository_id = ? ORDER BY id DESC LIMIT 1",
			repositoryID,
		)
	}

	if err != nil {
		return nil, false, err
	}

	return dest, found, nil
}

// RecordDependabotEvent inserts a row into ds_dependabot_events as well as any ds_dependabot_requested_snapshots rows
func (r *MySQLSnapshotsAdapter) RecordDependabotEvent(ctx context.Context, repositoryID uint64, eventType interfaces.EventType, ref string, sha string, pushID *uint64, entries []interfaces.DependabotRequestedSnapshot) (eventID uint64, returnErr error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "RecordDependabotEvent", "RecordDependabotEvent",
		kvp.Int64("gh.repo.id", int64(repositoryID)),
		kvp.String("event_type", string(eventType)),
		kvp.String("ref", ref),
		kvp.String("sha", sha),
		kvp.Int("snapshots_requested", len(entries)),
	)
	defer ender()

	tx, err := r.DB.BeginTxx(ctx, &sql.TxOptions{
		Isolation: sql.LevelReadCommitted,
	})
	if err != nil {
		return 0, errors.Wrap(err, "failed to begin transaction")
	}

	defer func() {
		if p := recover(); p != nil {
			tx.Rollback() // nolint: errcheck
			panic(p)
		}
		if returnErr != nil {
			txErr := tx.Rollback()
			if txErr != nil {
				returnErr = errors.Wrapf(returnErr, "with tx rollback error: %s", txErr)
			}
		}
	}()

	now := time.Now()

	res, err := ExecuteQuery(ctx, tx, "InsertDependabotEvent",
		"INSERT INTO ds_dependabot_events (repository_id, event_type, ref, sha, push_id, created_at) VALUES (?, ?, ?, ?, ?, ?)",
		repositoryID, string(eventType), ref, sha, pushID, now,
	)
	if err != nil {
		return 0, errors.Wrap(err, "failed to insert dependabot event")
	}

	eventIDInt, err := res.LastInsertId()
	if err != nil {
		return 0, errors.Wrap(err, "failed to get last insert id for dependabot event")
	}
	eventID = uint64(eventIDInt)

	//  TODO(brrygrdn):Change to a batch insert
	//
	// This should do a single insert for all requested snapshots unless entries is empty.
	for _, entry := range entries {
		pathHash := fmt.Sprintf("%x", sha256.Sum256([]byte(entry.ManifestPath)))
		_, err := ExecuteQuery(ctx, tx, "InsertDependabotRequestedSnapshot",
			"INSERT INTO ds_dependabot_requested_snapshots (event_id, ecosystem, manifest_path_hash, manifest_path_display, deadline, created_at) VALUES (?, ?, ?, ?, ?, ?)",
			eventID, entry.Ecosystem, pathHash, entry.ManifestPath, entry.Deadline, now,
		)
		if err != nil {
			return 0, errors.Wrapf(err, "failed to insert requested snapshot for ecosystem=%s path=%s", entry.Ecosystem, entry.ManifestPath)
		}
	}

	if err := tx.Commit(); err != nil {
		return 0, errors.Wrap(err, "failed to commit transaction")
	}

	contextlogger.Info(ctx, "RecordDependabotEvent: complete",
		kvp.Uint64("event_id", eventID),
		kvp.Int("requested_snapshots", len(entries)),
	)

	r.Statter.Counter("record_dependabot_event.success", stats.Tags{
		"event_type": string(eventType),
	}, 1)

	return eventID, nil
}

// GetEventDeadline retrieves the deadline for a given event's requested snapshots.
// All requested snapshots for a given event share the same deadline, so we return the first one found.
// Returns the deadline, a boolean indicating if a deadline was found, and any error.
func (r *MySQLSnapshotsAdapter) GetEventDeadline(ctx context.Context, eventID uint64) (time.Time, bool, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "GetEventDeadline", "GetEventDeadline",
		kvp.Uint64("event_id", eventID),
	)
	defer ender()

	type deadlineRow struct {
		Deadline time.Time `db:"deadline"`
	}
	dest := &deadlineRow{}
	found, err := QueryRow(ctx, r.DB, dest, "GetEventDeadline",
		"SELECT deadline FROM ds_dependabot_requested_snapshots WHERE event_id = ? ORDER BY deadline LIMIT 1",
		eventID,
	)
	if err != nil {
		return time.Time{}, false, errors.Wrap(err, "failed to get event deadline")
	}
	if !found {
		return time.Time{}, false, nil
	}

	return dest.Deadline, true, nil
}

// MarkDependabotSnapshotReceived updates a requested snapshot entry as received. Returns the number of rows affected (0 or 1).
func (r *MySQLSnapshotsAdapter) MarkDependabotSnapshotReceived(ctx context.Context, eventID uint64, ecosystem string, manifestPathHash string, snapshotID uint64) (int64, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MarkDependabotSnapshotReceived", "MarkDependabotSnapshotReceived",
		kvp.Uint64("event_id", eventID),
		kvp.String("ecosystem", ecosystem),
		kvp.String("manifest_path_hash", manifestPathHash),
		kvp.Int64("snapshot_id", int64(snapshotID)),
	)
	defer ender()

	res, err := ExecuteQuery(ctx, r.DB, "MarkDependabotSnapshotReceived",
		"UPDATE ds_dependabot_requested_snapshots SET snapshot_id = ?, received_at = ? WHERE event_id = ? AND ecosystem = ? AND manifest_path_hash = ? AND snapshot_id IS NULL",
		snapshotID, time.Now(), eventID, ecosystem, manifestPathHash,
	)
	if err != nil {
		return 0, errors.Wrap(err, "failed to mark dependabot snapshot received")
	}

	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return 0, errors.Wrap(err, "failed to get rows affected")
	}

	contextlogger.Info(ctx, "MarkDependabotSnapshotReceived: complete",
		kvp.Int64("rows_affected", rowsAffected),
	)

	r.Statter.Counter("mark_dependabot_snapshot_received", stats.Tags{
		"matched": fmt.Sprintf("%t", rowsAffected > 0),
	}, 1)

	return rowsAffected, nil
}

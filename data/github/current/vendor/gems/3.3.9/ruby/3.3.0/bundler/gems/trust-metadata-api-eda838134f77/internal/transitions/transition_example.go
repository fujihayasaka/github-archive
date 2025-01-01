package transitions

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	"github.com/jmoiron/sqlx"
)

// TransitionExample is an example of a backfill transition.
type TransitionExample struct {
	db     *sqlx.DB
	args   *Args
	logger log.Logger
}

// NewBackfillTransitionExample creates a new backfill transition.
func NewTransitionExample(db *sqlx.DB, args *Args, logger log.Logger) TransitionRunner {
	return &TransitionExample{
		db:     db,
		args:   args,
		logger: logger,
	}
}

// ArtifactRecord is a struct that represents a record in the attestations table.
type ArtifactRecord struct {
	ID            int    `db:"id"`
	PredicateType string `db:"predicate_type"`
}

// Run runs the transition.
func (t *TransitionExample) Run(_ context.Context) error {
	t.logger.Info("Running backfill example transition")

	// Define your query(s)
	startID, endID, batchSize := t.args.MinID, t.args.MaxID, t.args.BatchSize
	query := `SELECT id, predicate_type FROM attestations WHERE id BETWEEN ? AND ? LIMIT ?`

	// Process/move data in batches
	// All this example does is run a simple query and log the results

	// Loop through the attestations table in batches
	for startID <= endID {
		t.logger.Info("Processing batch...", kvp.Uint64("Start ID", startID), kvp.Uint64("End ID", endID))
		rows, err := t.db.Queryx(query, startID, min(startID+batchSize-1, endID), batchSize)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			var id int
			var predicateType string
			if err := rows.Scan(&id, &predicateType); err != nil {
				return err
			}
			t.logger.Info("Processing record...", kvp.Int("ID", id), kvp.String("Predicate Type", predicateType))
		}
		if err := rows.Err(); err != nil {
			return err
		}

		t.logger.Info("Batch processed")

		startID += batchSize
	}

	// Finish the transition
	return nil
}

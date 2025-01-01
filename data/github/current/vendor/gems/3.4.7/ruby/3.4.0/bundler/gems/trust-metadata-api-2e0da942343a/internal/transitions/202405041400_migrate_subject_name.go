package transitions

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	"github.com/jmoiron/sqlx"
)

// MigrateSubjectName is an example of a backfill transition.
type MigrateSubjectName struct {
	db     *sqlx.DB
	args   *Args
	logger log.Logger
}

// NewMigrateSubjectName creates a new backfill transition.
func NewMigrateSubjectName(db *sqlx.DB, args *Args, logger log.Logger) TransitionRunner {
	return &MigrateSubjectName{
		db:     db,
		args:   args,
		logger: logger,
	}
}

// Run runs the transition.
func (t *MigrateSubjectName) Run(_ context.Context) error {
	t.logger.Info("Running 202405041400 subject_name backfill transition")

	// Define the query
	// Use MySQL JSON_EXTRACT to extract the subject name from the statement column
	batchSize := t.args.BatchSize
	query := `
	UPDATE attestations
  SET subject_name = JSON_UNQUOTE(JSON_EXTRACT(statement, "$.subject[0].name"))
  WHERE subject_name IS NULL
  LIMIT ?;
	`

	// Process data in batch
	t.logger.Info("Processing batch...", kvp.Uint64("Batch-Size", batchSize))

	result, err := t.db.Exec(query, batchSize)
	if err != nil {
		t.logger.Error("Batch failed", kvp.Err(err))
		return err
	}

	affected, err := result.RowsAffected()
	if err != nil {
		t.logger.Error("affected count failed", kvp.Err(err))
		return err
	}
	t.logger.Info("Batch processed", kvp.Int64("Records-Affected", affected))

	// Finish the transition
	return nil
}

package transitions

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/trust-metadata-api/internal/transitions/database"

	"github.com/jmoiron/sqlx"
)

/*
	This transition is a backfill transition that migrates the subject_name & subject_digest
	from the attestations table to the attestations_subjects table
*/

// MigrateSubjectName is a backfill transition.
type MigrateAttestationsSubjects struct {
	args   *Args
	logger log.Logger
}

// NewMigrateSubjectName creates a new MigrateAttestationsSubjects backfill transition.
func NewMigrateAttestationsSubjects(args *Args, logger log.Logger) TransitionRunner {
	return &MigrateAttestationsSubjects{
		args:   args,
		logger: logger,
	}
}

func (t *MigrateAttestationsSubjects) Run(_ context.Context) error {
	// create a primary database connection
	t.logger.Info("Establishing primary database connection...")
	dbPrimary, err := database.BuildDBConn(t.args.DBConfig, false, t.logger)
	if err != nil {
		t.logger.Error("failed to build primaary database connection...")
		return err
	}
	defer dbPrimary.Close()

	// create a read-only replica database connection
	t.logger.Info("Establishing read-only replica database connection...")
	dbReplica, err := database.BuildDBConn(t.args.DBConfig, true, t.logger)
	if err != nil {
		t.logger.Error("failed to build db connection...")
		return err
	}
	defer dbReplica.Close()

	return t.RunWithDBConn(dbPrimary, dbReplica)
}

// Run runs the transition.
func (t *MigrateAttestationsSubjects) RunWithDBConn(dbPrimary *sqlx.DB, dbReplica *sqlx.DB) error {
	t.logger.Info("Running 202409131200 attestations_subjects name backfill transition")

	// totalRowsAffected is the total number of rows affected by the transition at the end
	var totalRowsAffected int64

	// attestationSubject represents a row in the attestations subjects table
	type attestationSubject struct {
		ID            int64
		SubjectDigest string
		SubjectName   string
	}

	// search query
	startID, endID, batchSize := t.args.MinID, t.args.MaxID, t.args.BatchSize
	queryFind := `
	SELECT attestations.id,
       attestations.subject_digest,
       attestations.subject_name
  FROM   attestations
       LEFT JOIN attestations_subjects
              ON attestations.id = attestations_subjects.attestation_id
  WHERE  attestations_subjects.attestation_id IS NULL
	AND attestations.id BETWEEN ? AND ? LIMIT ?;
	`

	t.logger.Info("Processing...", kvp.Uint64("Start-ID", startID), kvp.Uint64("End-ID", endID), kvp.Uint64("Batch-Size", batchSize))

	// Loop through the attestations table in batches
	for startID <= endID {
		t.logger.Info("starting batch loop...", kvp.Uint64("Start-ID", startID))

		// find the subjects
		rows, err := dbReplica.Query(queryFind, startID, min(startID+batchSize-1, endID), batchSize)
		if err != nil {
			t.logger.Error("Batch failed", kvp.Err(err))
			return err
		}
		defer rows.Close()

		// collect the subjects
		var attestationSubjects []attestationSubject
		for rows.Next() {
			var record attestationSubject
			if err := rows.Scan(&record.ID, &record.SubjectDigest, &record.SubjectName); err != nil {
				t.logger.Error("Row scan failed", kvp.Err(err))
				return err
			}

			attestationSubjects = append(attestationSubjects, record)
		}

		if err := rows.Err(); err != nil {
			t.logger.Error("Rows iteration failed", kvp.Err(err))
			return err
		}

		// Check if there were zero rows returned, move to the next batch if so
		if len(attestationSubjects) == 0 {
			t.logger.Info("No rows returned for this batch", kvp.Uint64("Start-ID", startID), kvp.Uint64("Batch-Size", batchSize))
			startID += batchSize
			continue
		}

		// create the insert statement
		var values []interface{}
		insertSubjectsStatement := "INSERT INTO attestations_subjects (attestation_id, subject_name, subject_digest) VALUES "
		for i, subject := range attestationSubjects {
			if i > 0 {
				insertSubjectsStatement += ", "
			}
			insertSubjectsStatement += "(?, ?, ?)"
			values = append(values, subject.ID, subject.SubjectName, subject.SubjectDigest)
		}
		insertSubjectsStatement += ";"

		// insert the subjects
		result, err := dbPrimary.Exec(insertSubjectsStatement, values...)
		if err != nil {
			t.logger.Error("Insert failed", kvp.Err(err))
			return err
		}

		affected, err := result.RowsAffected()
		if err != nil {
			t.logger.Error("affected count failed", kvp.Err(err))
			return err
		}
		totalRowsAffected += affected
		t.logger.Info("Batch processed", kvp.Int64("Records-Affected", affected))

		// Move to the next batch
		startID += batchSize

		// take a nap zzzz
		time.Sleep(2 * time.Second)
	}

	t.logger.Info("Processing finished.", kvp.Int64("Total-Records-Affected", totalRowsAffected))

	// Finish the transition
	return nil
}

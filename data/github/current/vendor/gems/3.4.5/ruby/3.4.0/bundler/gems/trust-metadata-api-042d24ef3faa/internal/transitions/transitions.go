package transitions

import (
	"context"

	"github.com/github/github-telemetry-go/log"
	"github.com/jmoiron/sqlx"

	"github.com/github/trust-metadata-api/internal/transitions/database"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
)

// Entries is a collection of entries.
// Add new transitions here.
func Entries() []Entry {
	return []Entry{
		{
			// attestations_subjects transition
			ID:           202409131200,
			TransitionFn: NewMigrateAttestationsSubjects,
		},
		{
			ID:             202405041400,
			DbTransitionFn: NewMigrateSubjectName,
		},
		{
			ID:             202404021710,
			DbTransitionFn: NewTransitionExample,
		},
	}
}

// TransitionRunner is a function that runs a transition.
type TransitionRunner interface {
	Run(ctx context.Context) error
}

// Used by transitions that only require a write connection to the database.
type dbTransitionFunc func(*sqlx.DB, *Args, log.Logger) TransitionRunner

// Used by transitions that setup write & read connections to the database.
type transitionFunc func(*Args, log.Logger) TransitionRunner

// Used by transitions that require a connection to Azure Blob Storage
type azBlobTransitionFunc func(azureblob.Client, *Args, log.Logger) TransitionRunner

// Entry is a transition entry.
type Entry struct {
	ID                 uint
	DbTransitionFn     dbTransitionFunc
	AzBlobTransitionFn azBlobTransitionFunc
	TransitionFn       transitionFunc
}

// Args are the arguments for a transition.
type Args struct {
	ID        uint
	DryRun    bool
	BatchSize uint64
	MinID     uint64
	MaxID     uint64
	DBConfig  database.DBConfig
}

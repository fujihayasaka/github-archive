// Package managedanalyses contains shared functionality for managed analyses.
package managedanalyses

import (
	"context"
	"time"

	"github.com/github/turboscan/ts"
)

type CodeqlDB interface {
	WithTransaction(fn func(CodeqlDB) error) error

	// CodeqlRun
	CreateCodeqlRun(context.Context, *ts.CodeqlRun) error
	GetCodeqlRun(context.Context, ts.RepositoryEID, ts.WorkflowRunEID) (*ts.CodeqlRun, error)
	UpdateCodeqlRun(context.Context, *ts.CodeqlRun) error
	GetCodeqlRunByShaAndRef(ctx context.Context, repoID ts.RepositoryEID, sha ts.Sha, ref ts.Ref) (*ts.CodeqlRun, error)
	GetMostRecentCodeqlRun(ctx context.Context, repoID ts.RepositoryEID, config *ts.CodeqlConfig) (*ts.CodeqlRun, error)
	GetPendingRunsForRef(ctx context.Context, repoID ts.RepositoryEID, ref ts.Ref, olderThan time.Time) ([]ts.CodeqlRun, error)

	// CodeqlRepo
	CreateCodeqlRepo(ctx context.Context, codeqlRepo *ts.CodeqlRepo) error
	UpdateCodeqlRepo(context.Context, *ts.CodeqlRepo) error
	GetCodeqlRepo(context.Context, ts.RepositoryEID) (*ts.CodeqlRepo, error)
	DeleteCodeqlRepo(context.Context, ts.RepositoryEID) error

	// CodeqlConfig
	AdjustCodeqlConfigLanguages(context.Context, ts.CodeqlConfigID, ts.Languages, string) error
	CreateStagedCodeqlConfig(ctx context.Context, config *ts.CodeqlConfig) error
	PromoteCodeqlConfigToCurrent(ctx context.Context, config *ts.CodeqlConfig, repoID ts.RepositoryEID, runStatus *ts.CodeqlRunStatus) error
	DeprecateStagedCodeqlConfig(ctx context.Context, repoID ts.RepositoryEID, configID ts.CodeqlConfigID, runStatus *ts.CodeqlRunStatus) error
	DisableCodeqlConfigByRepo(ctx context.Context, repoID ts.RepositoryEID) error
	ReplaceCodeqlConfigInplace(ctx context.Context, config *ts.CodeqlConfig) error

	// CodeqlSchedule
	CreateCodeqlSchedule(ctx context.Context, repoID ts.RepositoryEID, nextRunAt time.Time) error
	GetRunnableCodeqlSchedules(ctx context.Context) ([]ts.CodeqlSchedule, error)
	UpdateCodeqlSchedule(ctx context.Context, schedule ts.CodeqlSchedule) error

	// Queries:
	// These are methods that ask questions about the data but do not modify it.
	// They have simple return types.
	PreviousRunExists(context.Context, ts.RepositoryEID, ts.Sha, ts.Ref) (bool, error)
	GetPotentiallyOnboardedRepositoryIDs(ctx context.Context, since *time.Time) ([]ts.RepositoryEID, *time.Time, error)
	CanAttemptJITValidation(ctx context.Context, repoID ts.RepositoryEID, templateVersion string, overallLimit int, recencyWindow time.Duration) (bool, error)
	HadNonScheduledRunsAfter(ctx context.Context, repoIDs []ts.RepositoryEID, after time.Time) (map[ts.RepositoryEID]bool, error)
	GetNextScheduledRunTime(ctx context.Context, repoID ts.RepositoryEID) (time.Time, error)
	IsEnabled(ctx context.Context, repoID ts.RepositoryEID) (bool, error)
	GetDisabledTime(ctx context.Context, repoID ts.RepositoryEID) (*time.Time, error)
	GetRepositoriesDisabledBetween(ctx context.Context, t1 time.Time, t2 time.Time) ([]ts.DisabledCodeqlRepo, error)
}

package root

import (
	"context"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
)

var workflowRunID ts.WorkflowRunEID = 1

func setup(t *testing.T, db *gorm.DB) (context.Context, *managedanalysis.Service) {
	t.Helper()

	ctx := context.Background()
	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)
	cfg, err := config.Load()
	require.NoError(t, err, "failed to retrieve configs")

	kc, err := cfg.NewKafkaConfig(logger, statter)
	require.NoError(t, err, "failed to create Kafka config")

	publisher, err := publishers.New(*kc, statter)
	require.NoError(t, err, "failed to create publisher")

	maDataService := managedanalysis.NewService(db, publisher)
	require.NoError(t, err, "failed to create Managed Analysis service")

	return ctx, maDataService
}

func codeqlRun() *ts.CodeqlRun {
	workflowRunID += 1
	return &ts.CodeqlRun{
		RepositoryID:  1,
		ActorLogin:    "actor",
		Workflow:      "some workflow",
		Ref:           []byte("refs/heads/main"),
		WorkflowRunID: workflowRunID,
		Status:        ts.CodeqlRunStatus_COMPLETED,
	}
}

func TestOldSteadyRunsDeleted(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx, maDataService := setup(t, db)

	// two old runs

	oldRun := codeqlRun()
	oldRun.RunType = ts.CodeqlRunType_STEADY
	err := maDataService.CreateCodeqlRun(ctx, oldRun)
	require.NoError(t, err, "failed to create CodeQL run")

	err = db.Model(&oldRun).UpdateColumn("updated_at", sqltime.Time{Time: oldRun.UpdatedAt.AddDate(0, 0, -(DeleteOlderThanInDays + 2))}).Error
	require.NoError(t, err)

	notSoOldRun := codeqlRun()
	notSoOldRun.RunType = ts.CodeqlRunType_STEADY
	err = maDataService.CreateCodeqlRun(ctx, notSoOldRun)
	require.NoError(t, err, "failed to create CodeQL run")

	err = db.Model(&notSoOldRun).UpdateColumn("updated_at", sqltime.Time{Time: notSoOldRun.UpdatedAt.AddDate(0, 0, -(DeleteOlderThanInDays + 1))}).Error
	require.NoError(t, err)

	// two new runs

	newRun1 := codeqlRun()
	newRun1.RunType = ts.CodeqlRunType_STEADY
	err = maDataService.CreateCodeqlRun(ctx, newRun1)
	require.NoError(t, err, "failed to create CodeQL run")

	newRun2 := codeqlRun()
	newRun2.RunType = ts.CodeqlRunType_STEADY
	err = maDataService.CreateCodeqlRun(ctx, newRun2)
	require.NoError(t, err, "failed to create CodeQL run")

	// garbage collector should leave the two new ones
	dbtest.RequireCount(t, 4, db.Model(&ts.CodeqlRun{}))
	require.NoError(t, run(db, ctx, DefaultBatchSize))

	var remainingIDs []ts.CodeqlRunID
	err = db.Model(&ts.CodeqlRun{}).Pluck("id", &remainingIDs).Error
	require.NoError(t, err)

	require.Len(t, remainingIDs, 2)
	require.Contains(t, remainingIDs, newRun1.ID)
	require.Contains(t, remainingIDs, newRun2.ID)
}

func TestOnlySteadyRunsAreDeleted(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx, maDataService := setup(t, db)

	// two old runs, one of which is a validation run
	oldValidationRun := codeqlRun()
	oldValidationRun.RunType = ts.CodeqlRunType_VALIDATION
	err := maDataService.CreateCodeqlRun(ctx, oldValidationRun)
	require.NoError(t, err, "failed to create CodeQL run")

	err = db.Model(&oldValidationRun).UpdateColumn("updated_at", sqltime.Time{Time: oldValidationRun.UpdatedAt.AddDate(0, 0, -(DeleteOlderThanInDays + 2))}).Error
	require.NoError(t, err)

	oldSteadyRun := codeqlRun()
	oldSteadyRun.RunType = ts.CodeqlRunType_STEADY
	err = maDataService.CreateCodeqlRun(ctx, oldSteadyRun)
	require.NoError(t, err, "failed to create CodeQL run")

	err = db.Model(&oldSteadyRun).UpdateColumn("updated_at", sqltime.Time{Time: oldSteadyRun.UpdatedAt.AddDate(0, 0, -(DeleteOlderThanInDays + 1))}).Error
	require.NoError(t, err)

	// two new runs

	newRun1 := codeqlRun()
	newRun1.RunType = ts.CodeqlRunType_STEADY
	err = maDataService.CreateCodeqlRun(ctx, newRun1)
	require.NoError(t, err, "failed to create CodeQL run")

	newRun2 := codeqlRun()
	newRun2.RunType = ts.CodeqlRunType_VALIDATION
	err = maDataService.CreateCodeqlRun(ctx, newRun2)
	require.NoError(t, err, "failed to create CodeQL run")

	// garbage collector should leave the two new ones and the validation old one

	dbtest.RequireCount(t, 4, db.Model(&ts.CodeqlRun{}))
	require.NoError(t, run(db, ctx, DefaultBatchSize))

	var remainingIDs []ts.CodeqlRunID
	err = db.Model(&ts.CodeqlRun{}).Pluck("id", &remainingIDs).Error
	require.NoError(t, err)

	require.Len(t, remainingIDs, 3)
	require.Contains(t, remainingIDs, newRun1.ID)
	require.Contains(t, remainingIDs, newRun2.ID)
}

func TestLatestRunForEachRepoIsKeptEvenIfOld(t *testing.T) {
	doTestLatestRunForEachRepoIsKeptEvenIfOld(t, DefaultBatchSize)
}

func TestWillSuccessfullyDoCleanupSpanningMultipleBatches(t *testing.T) {
	doTestLatestRunForEachRepoIsKeptEvenIfOld(t, 2)
}

func doTestLatestRunForEachRepoIsKeptEvenIfOld(t *testing.T, batchSize int) { //nolint:thelper
	// Don't call t.Helper() here, because this function is a test really

	db := dbtest.RequireConnection(t)
	ctx, maDataService := setup(t, db)

	// two old runs for same repo; the most recent should be kept

	// NB creation order matters as we find the latest one to keep by ID rather than by updated_at
	// This is a technical limitation, but it's fine in terms of how the data is used.
	// Additional context: https://github.com/github/code-scanning/issues/15170
	repo1Older := codeqlRun()
	repo1Older.RunType = ts.CodeqlRunType_STEADY
	err := maDataService.CreateCodeqlRun(ctx, repo1Older)
	require.NoError(t, err, "failed to create CodeQL run")

	err = db.Model(&repo1Older).UpdateColumn("updated_at", sqltime.Time{Time: repo1Older.UpdatedAt.AddDate(0, 0, -(DeleteOlderThanInDays + 5))}).Error
	require.NoError(t, err)

	repo1Old := codeqlRun()
	repo1Old.RunType = ts.CodeqlRunType_STEADY
	err = maDataService.CreateCodeqlRun(ctx, repo1Old)
	require.NoError(t, err, "failed to create CodeQL run")

	err = db.Model(&repo1Old).UpdateColumn("updated_at", sqltime.Time{Time: repo1Old.UpdatedAt.AddDate(0, 0, -(DeleteOlderThanInDays + 1))}).Error
	require.NoError(t, err)

	// repo 2 has an old and a new run, so its single old run can go

	repo2Old := codeqlRun()
	repo2Old.RunType = ts.CodeqlRunType_STEADY
	repo2Old.RepositoryID = 2
	err = maDataService.CreateCodeqlRun(ctx, repo2Old)
	require.NoError(t, err, "failed to create CodeQL run")

	err = db.Model(&repo2Old).UpdateColumn("updated_at", sqltime.Time{Time: repo2Old.UpdatedAt.AddDate(0, 0, -(DeleteOlderThanInDays + 1))}).Error
	require.NoError(t, err)

	repo2New := codeqlRun()
	repo2New.RunType = ts.CodeqlRunType_STEADY
	repo2New.RepositoryID = 2
	err = maDataService.CreateCodeqlRun(ctx, repo2New)
	require.NoError(t, err, "failed to create CodeQL run")

	// this repo has just an old run; that should be kept

	repo3sole := codeqlRun()
	repo3sole.RunType = ts.CodeqlRunType_STEADY
	repo3sole.RepositoryID = 3
	err = maDataService.CreateCodeqlRun(ctx, repo3sole)
	require.NoError(t, err, "failed to create CodeQL run")

	err = db.Model(&repo3sole).UpdateColumn("updated_at", sqltime.Time{Time: repo3sole.UpdatedAt.AddDate(0, 0, -(DeleteOlderThanInDays + 1))}).Error
	require.NoError(t, err)

	// and this repo has just a new run; obviously that should be kept too!

	repo4sole := codeqlRun()
	repo4sole.RunType = ts.CodeqlRunType_VALIDATION
	repo4sole.RepositoryID = 4
	err = maDataService.CreateCodeqlRun(ctx, repo4sole)
	require.NoError(t, err, "failed to create CodeQL run")

	// garbage collector should leave the most recent run for each repo regardless of age

	dbtest.RequireCount(t, 6, db.Model(&ts.CodeqlRun{}))
	require.NoError(t, run(db, ctx, batchSize))

	var remainingIDs []ts.CodeqlRunID
	err = db.Model(&ts.CodeqlRun{}).Pluck("id", &remainingIDs).Error
	require.NoError(t, err)

	require.Len(t, remainingIDs, 4)
	require.Contains(t, remainingIDs, repo1Old.ID)
	require.Contains(t, remainingIDs, repo2New.ID)
	require.Contains(t, remainingIDs, repo3sole.ID)
	require.Contains(t, remainingIDs, repo4sole.ID)
}

func TestWillSuccessfullyDoCleanupForOneRepoSpanningMultipleBatches(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx, maDataService := setup(t, db)

	var lastId ts.CodeqlRunID
	for i := 0; i < 10; i++ {
		run := codeqlRun()
		run.RunType = ts.CodeqlRunType_STEADY
		err := maDataService.CreateCodeqlRun(ctx, run)
		require.NoError(t, err, "failed to create CodeQL run")
		if i == 9 {
			lastId = run.ID
		}

		err = db.Model(&run).UpdateColumn("updated_at", sqltime.Time{Time: run.UpdatedAt.AddDate(0, 0, -(DeleteOlderThanInDays + 1))}).Error
		require.NoError(t, err)
	}

	dbtest.RequireCount(t, 10, db.Model(&ts.CodeqlRun{}))
	require.NoError(t, run(db, ctx, 2))

	var remainingIDs []ts.CodeqlRunID
	err := db.Model(&ts.CodeqlRun{}).Pluck("id", &remainingIDs).Error
	require.NoError(t, err)

	require.Len(t, remainingIDs, 1)
	require.Contains(t, remainingIDs, lastId)
}

func TestDoesNotErrorIfNoRuns(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx, _ := setup(t, db)

	require.NoError(t, run(db, ctx, DefaultBatchSize))
}

func TestDeletesNothingWhereAllRunsAreNew(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx, maDataService := setup(t, db)

	for i := 0; i < 10; i++ {
		run := codeqlRun()
		run.RunType = ts.CodeqlRunType_STEADY
		err := maDataService.CreateCodeqlRun(ctx, run)
		require.NoError(t, err, "failed to create CodeQL run")
	}

	dbtest.RequireCount(t, 10, db.Model(&ts.CodeqlRun{}))
	require.NoError(t, run(db, ctx, DefaultBatchSize))
	dbtest.RequireCount(t, 10, db.Model(&ts.CodeqlRun{}))
}

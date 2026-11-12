package repocheck_test

import (
	"testing"
	"testing/synctest"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dsapiclient"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/repocheck"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
)

func TestSnapshotReceivedWithUnknownCommit(t *testing.T) {
	r := require.New(t)
	ctx := t.Context()
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	r.NoError(err)
	r.NotNil(app)
	err = repocheck.SnapshotReceived(ctx, app, 1, "abc123")
	r.NoError(err)
}

func TestSnapshotReceivedWhenJobCompleteReturns(t *testing.T) {
	r := require.New(t)
	ctx := t.Context()
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	r.NoError(err)
	r.NotNil(app)
	baseCheckjob := models.CheckJob{
		RepositoryID: 1,
		CommitSHA:    "abc123",
	}
	checkjob, err := app.Subsystems.Storage.CreateCheckJob(ctx, baseCheckjob)
	r.NoError(err)
	checkjob.Status = models.Pass
	err = app.Subsystems.Storage.UpdateCheckJob(ctx, checkjob)
	r.NoError(err)
	err = repocheck.SnapshotReceived(ctx, app, 1, "abc123")
	r.NoError(err)
}

func TestSnapshotReceivedErrorCallingDSAPI(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		r := require.New(t)
		ctx := t.Context()
		var repoID uint64 = 500 // use repoID from snapshot_diff_status seeds that causes error
		commitSHA := "abc123"

		dsConfig, err := loadDiffStatusNullConfig()
		require.NoError(t, err)
		require.NotNil(t, dsConfig)

		app := newTestApp(t, &application.NullConfig{DiffStatusConfig: *dsConfig})

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		baseCheckjob := models.CheckJob{
			OrganizationID:    testhelpers.RandomIDForDatabase(),
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			CommitSHA:         commitSHA,
			BaseSHA:           "base-sha",
		}
		checkjob, err := app.Subsystems.Storage.CreateCheckJob(ctx, baseCheckjob)
		r.NoError(err)
		checkjob.Status = models.Waiting
		err = app.Subsystems.Storage.UpdateCheckJob(ctx, checkjob)
		r.NoError(err)
		dsapiErrMsg := "simulated error from DS-API client"
		err = repocheck.SnapshotReceived(ctx, app, repoID, commitSHA)
		r.Error(err)
		r.Contains(err.Error(), dsapiErrMsg)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR, commitSHA, repoID,
			"✗ Unable to complete check: Unable to check dependency snapshot status.",
			"License compliance check encountered an error")
	})
}

func TestSnapshotReceived_PublishesErrorProgressOnValidationError(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		r := require.New(t)
		ctx := t.Context()
		var repoID uint64 = 400 // use repoID from snapshot_diff_status seeds that are complete
		commitSHA := "target-sha"
		baseSHA := "base-sha"

		dsConfig, err := loadDiffStatusNullConfig()
		require.NoError(t, err)

		app := newTestApp(t, &application.NullConfig{DiffStatusConfig: *dsConfig})

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		// Create a check job with missing fields that will cause validation to fail
		// OrganizationID=0 and PullRequestNumber=0 will trigger a ValidationError
		baseCheckjob := models.CheckJob{
			OrganizationID:    0,
			RepositoryID:      repoID,
			PullRequestNumber: 0,
			CommitSHA:         commitSHA,
			BaseSHA:           baseSHA,
			Status:            models.Waiting,
		}
		_, err = app.Subsystems.Storage.CreateCheckJob(ctx, baseCheckjob)
		r.NoError(err)

		// SnapshotReceived should return nil (not retry malformed messages)
		err = repocheck.SnapshotReceived(ctx, app, repoID, commitSHA)
		r.NoError(err)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR, commitSHA, repoID,
			"✗ Unable to complete check: Missing required information.",
			"License compliance check encountered an error")

		// Check job should be set to Error status
		updatedJob, err := app.Subsystems.Storage.GetCheckJobByCommit(ctx, repoID, commitSHA)
		r.NoError(err)
		r.NotNil(updatedJob)
		r.Equal(models.Error, updatedJob.Status)
	})
}

func TestSnapshotReceivedStillWaiting(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		r := require.New(t)
		ctx := t.Context()
		var repoID uint64 = 200 // use repoID from snapshot_diff_status seeds that requires waiting
		var prNum uint32 = 11
		commitSHA := "target-sha"
		baseSHA := "base-sha"

		dsConfig, err := loadDiffStatusNullConfig()
		require.NoError(t, err)
		require.NotNil(t, dsConfig)

		app := newTestApp(t, &application.NullConfig{DiffStatusConfig: *dsConfig})
		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		baseCheckjob := models.CheckJob{
			OrganizationID:    1,
			RepositoryID:      repoID,
			CommitSHA:         commitSHA,
			BaseSHA:           baseSHA,
			PullRequestNumber: prNum,
			ExpectedSnapshots: 5,
			ReceivedSnapshots: 1,
		}
		checkjob, err := app.Subsystems.Storage.CreateCheckJob(ctx, baseCheckjob)
		r.NoError(err)
		checkjob.Status = models.Waiting
		err = app.Subsystems.Storage.UpdateCheckJob(ctx, checkjob)
		r.NoError(err)
		err = repocheck.SnapshotReceived(ctx, app, repoID, commitSHA)
		r.NoError(err)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_WAITING, commitSHA, repoID,
			"Waiting for dependency snapshots on head (2/5 received)... Missing snapshots from detectors: detector-one, detector-two.", "")

		updatedJob, err := app.Subsystems.Storage.GetCheckJob(ctx, repoID, prNum)
		r.NoError(err)
		r.NotNil(updatedJob)
		r.Equal(models.Waiting, updatedJob.Status)
		r.Equal(uint32(2), updatedJob.ReceivedSnapshots)
		r.Equal(uint32(5), updatedJob.ExpectedSnapshots)
		r.Equal([]string{"detector-one", "detector-two"}, updatedJob.MissingDetectors)
	})
}

func TestSnapshotReceivedStillWaiting_DependabotPending(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		r := require.New(t)
		ctx := t.Context()
		var repoID uint64 = 600 // use repoID from seeds where dependabot_pending is true
		var prNum uint32 = 12
		commitSHA := "target-sha"
		baseSHA := "base-sha"

		dsConfig, err := loadDiffStatusNullConfig()
		require.NoError(t, err)
		require.NotNil(t, dsConfig)

		app := newTestApp(t, &application.NullConfig{DiffStatusConfig: *dsConfig})
		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		baseCheckjob := models.CheckJob{
			OrganizationID:    1,
			RepositoryID:      repoID,
			CommitSHA:         commitSHA,
			BaseSHA:           baseSHA,
			PullRequestNumber: prNum,
			ExpectedSnapshots: 3,
			ReceivedSnapshots: 3,
		}
		checkjob, err := app.Subsystems.Storage.CreateCheckJob(ctx, baseCheckjob)
		r.NoError(err)
		checkjob.Status = models.Waiting
		err = app.Subsystems.Storage.UpdateCheckJob(ctx, checkjob)
		r.NoError(err)
		err = repocheck.SnapshotReceived(ctx, app, repoID, commitSHA)
		r.NoError(err)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_WAITING, commitSHA, repoID,
			"Waiting for Dependabot graph update jobs to complete.", "")

		updatedJob, err := app.Subsystems.Storage.GetCheckJob(ctx, repoID, prNum)
		r.NoError(err)
		r.NotNil(updatedJob)
		r.Equal(models.Waiting, updatedJob.Status)
		r.Equal(uint32(3), updatedJob.ReceivedSnapshots)
		r.Equal(uint32(3), updatedJob.ExpectedSnapshots)
		r.Equal([]string{}, updatedJob.MissingDetectors)
		r.True(updatedJob.DependabotPending)
	})
}

func TestSnapshotReceivedCheckRunsAndFails(t *testing.T) {
	r := require.New(t)
	ctx := t.Context()

	orgID := testhelpers.RandomIDForDatabase()
	var repoID uint64 = 400 // use repoID from snapshot_diff_status seeds that are complete
	commitSHA := "target-sha"
	baseSHA := "base-sha"

	// add snapshot diff status null config that holds seed values
	dsConfig, err := loadDiffStatusNullConfig()
	require.NoError(t, err)
	require.NotNil(t, dsConfig)
	nullConfig := &application.NullConfig{
		DiffStatusConfig: *dsConfig,
	}
	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "MIT", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nullConfig)

	// create the initial CheckJob record with more snapshots expected to be received
	baseCheckJob := models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		Status:            models.Starting,
		ExpectedSnapshots: 0,
		ReceivedSnapshots: 0,
	}
	checkJob, err := app.Subsystems.Storage.CreateCheckJob(ctx, baseCheckJob)
	r.NoError(err)
	require.NoError(t, err)
	require.Equal(t, models.Starting.String(), checkJob.Status.String())

	checkJob.ExpectedSnapshots = 3
	checkJob.ReceivedSnapshots = 2
	checkJob.Status = models.Waiting
	checkJob.MissingDetectors = []string{"detector-one", "detector-two"} // simulate a stale value persisted while we were Waiting
	err = app.Subsystems.Storage.UpdateCheckJob(ctx, checkJob)
	r.NoError(err)

	// last snapshot is received and the license check will run
	err = repocheck.SnapshotReceived(ctx, app, repoID, commitSHA)
	r.NoError(err)

	// verify CheckJob was updated with a final status of Fail and all snapshots received which is required for the license check to run
	updatedJob, err := app.Subsystems.Storage.GetCheckJob(ctx, repoID, testhelpers.PR42AsUint32)
	r.NoError(err)
	r.NotNil(updatedJob)
	r.Equal(models.Fail.String(), updatedJob.Status.String(), "updatedJob status should be Fail")
	r.Equal(uint32(3), updatedJob.ReceivedSnapshots)
	r.Equal(uint32(3), updatedJob.ExpectedSnapshots)
	r.Equal([]string{}, updatedJob.MissingDetectors, "MissingDetectors should be cleared once all snapshots are received")
}

func TestGetSnapshotStatus_ResultsWithNoSnapshots(t *testing.T) {
	repoID := uint64(100)     // Use repo ID that exists in seeds
	commitSHA := "target-sha" // Use commit SHA from seeds
	baseSHA := "base-sha"     // Use base SHA from seeds

	dsConfig, err := loadDiffStatusNullConfig()
	require.NoError(t, err)
	require.NotNil(t, dsConfig)

	nullConfig := &application.NullConfig{DiffStatusConfig: *dsConfig}
	app, err := application.NewNullApplication(nullConfig, log.NewNullLogger())
	require.NoError(t, err)
	require.NotNil(t, app)

	diffStatus, err := repocheck.GetSnapshotStatus(t.Context(), app.Logger, app.Subsystems.DiffStatusGetter, repoID, commitSHA, baseSHA, 0, 0)
	require.NoError(t, err)

	// expected values come from the seeds file
	assert.False(t, diffStatus.IsWaiting())
	assert.Equal(t, &repocheck.SnapshotDiffStatus{
		Expected:         0,
		Received:         0,
		MissingDetectors: []string{},
	}, diffStatus)
}

func TestGetSnapshotStatus_ExpectedGtReceived(t *testing.T) {
	repoID := uint64(200)     // Use repo ID that exists in seeds
	commitSHA := "target-sha" // Use commit SHA from seeds
	baseSHA := "base-sha"     // Use base SHA from seeds

	dsConfig, err := loadDiffStatusNullConfig()
	require.NoError(t, err)
	require.NotNil(t, dsConfig)

	nullConfig := &application.NullConfig{DiffStatusConfig: *dsConfig}
	app, err := application.NewNullApplication(nullConfig, log.NewNullLogger())
	require.NoError(t, err)
	require.NotNil(t, app)

	diffStatus, err := repocheck.GetSnapshotStatus(t.Context(), app.Logger, app.Subsystems.DiffStatusGetter, repoID, commitSHA, baseSHA, 0, 0)
	require.NoError(t, err)

	// expected values come from the seeds file
	assert.True(t, diffStatus.IsWaiting())
	assert.Equal(t, &repocheck.SnapshotDiffStatus{
		Expected:         5,
		Received:         2,
		MissingDetectors: []string{"detector-one", "detector-two"},
	}, diffStatus)
}

func TestGetSnapshotStatus_ReceivedGtExpected(t *testing.T) {
	repoID := uint64(300)     // Use repo ID that exists in seeds
	commitSHA := "target-sha" // Use commit SHA from seeds
	baseSHA := "base-sha"     // Use base SHA from seeds

	dsConfig, err := loadDiffStatusNullConfig()
	require.NoError(t, err)
	require.NotNil(t, dsConfig)

	nullConfig := &application.NullConfig{DiffStatusConfig: *dsConfig}
	app, err := application.NewNullApplication(nullConfig, log.NewNullLogger())
	require.NoError(t, err)
	require.NotNil(t, app)

	diffStatus, err := repocheck.GetSnapshotStatus(t.Context(), app.Logger, app.Subsystems.DiffStatusGetter, repoID, commitSHA, baseSHA, 0, 0)
	require.NoError(t, err)

	// expected values come from the seeds file
	assert.False(t, diffStatus.IsWaiting())
	assert.Equal(t, &repocheck.SnapshotDiffStatus{
		Expected:         10,
		Received:         11,
		MissingDetectors: []string{},
	}, diffStatus)
}

func TestGetSnapshotStatus_DependabotPending(t *testing.T) {
	repoID := uint64(600)     // Use repo ID from seeds where dependabot_pending is true
	commitSHA := "target-sha" // Use commit SHA from seeds
	baseSHA := "base-sha"     // Use base SHA from seeds

	dsConfig, err := loadDiffStatusNullConfig()
	require.NoError(t, err)
	require.NotNil(t, dsConfig)

	nullConfig := &application.NullConfig{DiffStatusConfig: *dsConfig}
	app, err := application.NewNullApplication(nullConfig, log.NewNullLogger())
	require.NoError(t, err)
	require.NotNil(t, app)

	diffStatus, err := repocheck.GetSnapshotStatus(t.Context(), app.Logger, app.Subsystems.DiffStatusGetter, repoID, commitSHA, baseSHA, 0, 0)
	require.NoError(t, err)

	// All detector snapshots received, but Dependabot is still pending
	assert.True(t, diffStatus.IsWaiting())
	assert.Equal(t, &repocheck.SnapshotDiffStatus{
		Expected:          3,
		Received:          3,
		MissingDetectors:  []string{},
		DependabotPending: true,
	}, diffStatus)
}

func TestSnapshotDiffStatus_IsWaiting(t *testing.T) {
	tests := []struct {
		name   string
		status repocheck.SnapshotDiffStatus
		want   bool
	}{
		{
			name:   "not waiting when counts match",
			status: repocheck.SnapshotDiffStatus{Expected: 3, Received: 3},
			want:   false,
		},
		{
			name:   "waiting when received less than expected",
			status: repocheck.SnapshotDiffStatus{Expected: 5, Received: 2},
			want:   true,
		},
		{
			name:   "waiting when dependabot pending even if counts match",
			status: repocheck.SnapshotDiffStatus{Expected: 3, Received: 3, DependabotPending: true},
			want:   true,
		},
		{
			name:   "waiting when both detectors and dependabot pending",
			status: repocheck.SnapshotDiffStatus{Expected: 5, Received: 2, DependabotPending: true},
			want:   true,
		},
		{
			name:   "not waiting when zero counts and no dependabot",
			status: repocheck.SnapshotDiffStatus{Expected: 0, Received: 0},
			want:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, tt.status.IsWaiting())
		})
	}
}

func loadDiffStatusNullConfig() (*dsapiclient.NullConfig, error) {
	diffStatusConfig, err := dsapiclient.LoadNullSeeds(
		"../../null_seeds/snapshots_diff_status.json",
	)
	if err != nil {
		return nil, err
	}
	return &diffStatusConfig, nil
}

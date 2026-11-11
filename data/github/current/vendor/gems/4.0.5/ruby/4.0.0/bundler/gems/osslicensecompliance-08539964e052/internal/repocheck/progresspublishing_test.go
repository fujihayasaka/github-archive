package repocheck_test

import (
	"testing"
	"testing/synctest"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/repocheck"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
)

func assertProgressEventPublished(t *testing.T, tp *testpublisher.TestPublisher, expectedStatus entities.CheckJobStatus, commitSHA string, repoID uint64, logMessage, title string) {
	t.Helper()

	var titleWrapper *wrapperspb.StringValue
	if title != "" {
		titleWrapper = &wrapperspb.StringValue{Value: title}
	}

	expectedProto := &dependencygraphv1.PullRequestLicenseCheckProgressed{
		CheckJobStatus: expectedStatus,
		CommitSha:      commitSHA,
		RepositoryId:   int64(repoID),
		LogMessage:     logMessage,
		ProgressedAt:   timestamppb.New(time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)),
		Title:          titleWrapper,
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckProgressed", expectedProto)
}

func newTestApp(t *testing.T, cfg *application.NullConfig) *application.Application {
	t.Helper()
	if cfg == nil {
		cfg = &application.NullConfig{}
	}
	app, err := application.NewNullApplication(cfg, log.NewNullLogger())
	require.NoError(t, err)
	t.Cleanup(func() {
		err = app.Close()
		if err != nil {
			t.Errorf("failed to close app: %v", err)
		}
	})
	return app
}

func TestStart_PublishesProgress_NotWaiting(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		repoID := uint64(100) // Seeds: 0 expected, 0 received => not waiting
		orgID := testhelpers.RandomIDForDatabase()
		baseSHA := "base-sha"
		commitSHA := "commit-sha"

		app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestID:     testhelpers.RandomIDForDatabase(),
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Context:           "distributed",
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err := checker.Start(t.Context(), nil, checkRequest)
		require.NoError(t, err)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_STARTING, commitSHA, repoID,
			"Starting license check...", "")
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_RUNNING, commitSHA, repoID,
			"Evaluating dependencies against license policy...", "")
		// Skip PullRequestLicenseCheckComplete event published by UpdateAlerts
		tp.SkipMessage(t)
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_PASS, commitSHA, repoID,
			"✓ License check passed",
			"No new license compliance alerts in code changed by this pull request")
		tp.AssertNoMessagePublished(t)
	})
}

func TestStart_PublishesProgress_Waiting(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		repoID := uint64(200) // Seeds: 5 expected, 2 received => waiting
		orgID := testhelpers.RandomIDForDatabase()
		commitSHA := "target-sha"
		baseSHA := "base-sha"

		dsConfig, err := loadDiffStatusNullConfig()
		require.NoError(t, err)

		app := newTestApp(t, &application.NullConfig{DiffStatusConfig: *dsConfig})

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestID:     testhelpers.RandomIDForDatabase(),
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.Start(t.Context(), nil, checkRequest)
		require.NoError(t, err)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_STARTING, commitSHA, repoID,
			"Starting license check...", "")
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_WAITING, commitSHA, repoID,
			"Waiting for dependency snapshots on head (2/5 received)... Missing snapshots from detectors: detector-one, detector-two.", "")
		tp.AssertNoMessagePublished(t)
	})
}

func TestStart_PublishesErrorProgressOnCheckJobCreationFailure(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		app := newTestApp(t, nil)
		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		orgID := testhelpers.RandomIDForDatabase()
		repoID := testhelpers.RandomIDForDatabase()

		// Close DB to force CreateCheckJob to fail
		err := app.Subsystems.Storage.Close()
		require.NoError(t, err)

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestID:     testhelpers.RandomIDForDatabase(),
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           "base-sha",
			CommitSHA:         "target-sha",
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.Start(t.Context(), nil, checkRequest)
		require.Error(t, err)
		require.ErrorIs(t, err, repocheck.ErrCheckJobCreation)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR, "target-sha", repoID,
			"✗ Unable to complete check: Unable to start license check.",
			"License compliance check encountered an error")
	})
}

func TestStart_PublishesErrorProgressOnUpdateCheckJobError(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		repoID := uint64(100) // Seeds: 0 expected snapshots
		orgID := testhelpers.RandomIDForDatabase()
		commitSHA := "target-sha"
		baseSHA := "base-sha"

		dsConfig, err := loadDiffStatusNullConfig()
		require.NoError(t, err)

		app := newTestApp(t, &application.NullConfig{DiffStatusConfig: *dsConfig})

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
			RepositoryID:      repoID,
			OrganizationID:    orgID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Status:            models.Starting,
		})
		require.NoError(t, err)

		// Close DB to force UpdateCheckJob to fail
		err = app.Subsystems.Storage.Close()
		require.NoError(t, err)

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestID:     testhelpers.RandomIDForDatabase(),
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.Start(t.Context(), checkJob, checkRequest)
		require.Error(t, err)
		require.ErrorIs(t, err, repocheck.ErrCheckJobUpdate)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_STARTING, commitSHA, repoID,
			"Starting license check...", "")
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR, commitSHA, repoID,
			"✗ Unable to complete check: Unable to update license check status.",
			"License compliance check encountered an error")
	})
}

func TestStart_PublishesErrorProgressOnGetSnapshotStatusError(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		repoID := uint64(500) // repo ID 500 triggers a simulated DS-API error
		orgID := testhelpers.RandomIDForDatabase()
		commitSHA := "target-sha"
		baseSHA := "base-sha"

		dsConfig, err := loadDiffStatusNullConfig()
		require.NoError(t, err)

		app := newTestApp(t, &application.NullConfig{DiffStatusConfig: *dsConfig})

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestID:     testhelpers.RandomIDForDatabase(),
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.Start(t.Context(), nil, checkRequest)
		require.Error(t, err)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_STARTING, commitSHA, repoID,
			"Starting license check...", "")
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR, commitSHA, repoID,
			"✗ Unable to complete check: Unable to check dependency snapshot status.",
			"License compliance check encountered an error")

		// Verify check job status was set to Error
		updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
		require.NoError(t, err)
		assert.Equal(t, models.Error, updatedJob.Status)
	})
}

func TestStart_ClearsMissingDetectorsWhenNotWaiting(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		repoID := uint64(100) // Seeds: 0 expected, 0 received => not waiting
		orgID := testhelpers.RandomIDForDatabase()
		baseSHA := "base-sha"
		commitSHA := "commit-sha"

		app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		// Seed an existing CheckJob with stale MissingDetectors from a prior Waiting state.
		existing, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Status:            models.Waiting,
			MissingDetectors:  []string{"detector-one", "detector-two"},
		})
		require.NoError(t, err)
		require.Equal(t, []string{"detector-one", "detector-two"}, existing.MissingDetectors)

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestID:     testhelpers.RandomIDForDatabase(),
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Context:           "distributed",
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		require.NoError(t, checker.Start(t.Context(), existing, checkRequest))

		updated, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
		require.NoError(t, err)
		require.NotNil(t, updated)
		assert.Equal(t, []string{}, updated.MissingDetectors, "MissingDetectors should be cleared once snapshot status is no longer waiting")
	})
}

func TestExecuteJob_PublishesProgress_Pass(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		orgID := testhelpers.RandomIDForDatabase()
		repoID := testhelpers.RandomIDForDatabase()
		baseSHA := "basesha"
		commitSHA := "sha"

		app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)
		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Status:            models.Starting,
		})
		require.NoError(t, err)

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestID:     testhelpers.RandomIDForDatabase(),
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Context:           "distributed",
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.ExecuteJob(t.Context(), checkJob, checkRequest)
		require.NoError(t, err)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_RUNNING, commitSHA, repoID,
			"Evaluating dependencies against license policy...", "")
		// Skip PullRequestLicenseCheckComplete event published by UpdateAlerts
		tp.SkipMessage(t)
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_PASS, commitSHA, repoID,
			"✓ License check passed",
			"No new license compliance alerts in code changed by this pull request")
	})
}

func TestExecuteJob_PublishesProgress_Fail(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		orgID := testhelpers.RandomIDForDatabase()
		repoID := testhelpers.RandomIDForDatabase()
		baseSHA := "basesha"
		commitSHA := "sha"

		// dep has BSD-3-Clause but policy only allows MIT => fail
		app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "MIT", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)
		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Status:            models.Starting,
		})
		require.NoError(t, err)

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestID:     testhelpers.RandomIDForDatabase(),
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Context:           "distributed",
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.ExecuteJob(t.Context(), checkJob, checkRequest)
		require.NoError(t, err)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_RUNNING, commitSHA, repoID,
			"Evaluating dependencies against license policy...", "")
		// Skip PullRequestLicenseCheckComplete event published by UpdateAlerts
		tp.SkipMessage(t)
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_FAIL, commitSHA, repoID,
			"✗ License check completed with violations. See the comment from license-compliance-bot on this pull request for details.",
			"1 new license compliance alert")
	})
}

func TestExecuteJob_PublishesErrorProgressOnInitialUpdateCheckJobError(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		app := newTestApp(t, nil)
		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		repoID := testhelpers.RandomIDForDatabase()
		orgID := testhelpers.RandomIDForDatabase()
		commitSHA := "commit-sha"
		baseSHA := "base-sha"

		checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Status:            models.Starting,
		})
		require.NoError(t, err)

		// Close DB to force UpdateCheckJob to fail
		err = app.Subsystems.Storage.Close()
		require.NoError(t, err)

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Context:           "distributed",
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.ExecuteJob(t.Context(), checkJob, checkRequest)
		require.ErrorIs(t, err, repocheck.ErrCheckJobUpdate)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR, commitSHA, repoID,
			"✗ Unable to complete check: Unable to update license check status.",
			"License compliance check encountered an error")
	})
}

func TestExecuteJob_PublishesErrorProgressOnGetCompletePolicyWithVersionError(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		app := newTestApp(t, nil)
		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		repoID := testhelpers.RandomIDForDatabase()
		orgID := testhelpers.RandomIDForDatabase()
		commitSHA := "commit-sha"
		baseSHA := "base-sha"

		checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Status:            models.Starting,
		})
		require.NoError(t, err)

		// No policy is created, so GetCompletePolicyWithVersion will return ErrNotFound.

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Context:           "distributed",
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.ExecuteJob(t.Context(), checkJob, checkRequest)
		require.Error(t, err)
		require.ErrorIs(t, err, repocheck.ErrPolicyNotFound)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_RUNNING, commitSHA, repoID,
			"Evaluating dependencies against license policy...", "")
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR, commitSHA, repoID,
			"✗ Unable to complete check: No license policy is configured for this repository.",
			"License compliance check encountered an error")

		// Verify check job status was set to Error
		updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
		require.NoError(t, err)
		assert.Equal(t, models.Error, updatedJob.Status)
	})
}

func TestExecuteJob_PublishesErrorProgressOnPolicyLoadError(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		orgID := testhelpers.RandomIDForDatabase()
		repoID := testhelpers.RandomIDForDatabase()
		baseSHA := "basesha"
		commitSHA := "sha"

		// Build storage with explicit bucket references so we can selectively close the org bucket
		// to force GetCompletePolicyWithVersion to fail with a non-ErrNotFound error (ErrPolicyLoad branch).
		repoBucket := storage.NewNullBucket()
		orgBucket := storage.NewNullBucket()
		entBucket := storage.NewNullBucket()
		st, err := storage.NewNullStorageWithBuckets("", repoBucket, orgBucket, entBucket, log.NewNullLogger())
		require.NoError(t, err)

		policy := &proto.OrganizationPolicy{
			OrganizationId:       orgID,
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"BSD-3-Clause"}, nil, testhelpers.AllDistributionContexts),
		}
		_, err = st.CreateOrganizationPolicy(t.Context(), policy)
		require.NoError(t, err)

		err = orgBucket.Close()
		require.NoError(t, err)

		checkJob, err := st.CreateCheckJob(t.Context(), models.CheckJob{
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Status:            models.Starting,
		})
		require.NoError(t, err)

		// Wire up the Application with our custom storage
		app := newTestApp(t, nil)
		// Close original storage before replacing it to avoid leaking its DB goroutine.
		err = app.Subsystems.Storage.Close()
		require.NoError(t, err)

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.Storage = st
		app.Subsystems.EventPublisher = tp.Publisher

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Context:           "distributed",
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.ExecuteJob(t.Context(), checkJob, checkRequest)
		require.Error(t, err)
		require.ErrorIs(t, err, repocheck.ErrPolicyLoad)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_RUNNING, commitSHA, repoID,
			"Evaluating dependencies against license policy...", "")
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR, commitSHA, repoID,
			"✗ Unable to complete check: Unable to load license policy.",
			"License compliance check encountered an error")

		// Verify check job status was set to Error
		updatedJob, err := st.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
		require.NoError(t, err)
		assert.Equal(t, models.Error, updatedJob.Status)
	})
}

func TestExecuteJob_PublishesErrorProgressOnDependencyFetchError(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		orgID := testhelpers.RandomIDForDatabase()
		repoID := testhelpers.RandomIDForDatabase()
		baseSHA := "basesha"
		commitSHA := "sha"

		app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)
		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		// Replace the ShaDiffGetter with one that always returns an error
		app.Subsystems.DependencyGetter.ShaDiffGetter = dependencies.DGShaDiffErrorStub{}

		checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Status:            models.Starting,
		})
		require.NoError(t, err)

		checkRequest := &repocheck.Request{
			EnterpriseID:      0,
			OrganizationID:    orgID,
			RepositoryID:      repoID,
			PullRequestNumber: testhelpers.PR42AsUint32,
			BaseSHA:           baseSHA,
			CommitSHA:         commitSHA,
			Context:           "distributed",
		}

		checker := repocheck.NewChecker(app, app.StatsClient)
		err = checker.ExecuteJob(t.Context(), checkJob, checkRequest)
		require.Error(t, err)
		require.ErrorIs(t, err, repocheck.ErrDependencyFetch)

		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_RUNNING, commitSHA, repoID,
			"Evaluating dependencies against license policy...", "")
		assertProgressEventPublished(t, tp, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR, commitSHA, repoID,
			"✗ Unable to complete check: Unable to retrieve dependency information.",
			"License compliance check encountered an error")

		// Verify check job status was set to Error
		updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
		require.NoError(t, err)
		assert.Equal(t, models.Error, updatedJob.Status)
	})
}

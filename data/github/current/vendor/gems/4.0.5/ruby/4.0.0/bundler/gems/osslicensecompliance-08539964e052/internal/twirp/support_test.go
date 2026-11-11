package twirp

import (
	"errors"
	"math"
	"testing"
	"testing/synctest"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestCheckStatus_InternalErrorWhenStorageErrors(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// Close DB to force an unexpected error with GetCheckJob
	err = server.app.Subsystems.Storage.Close()
	require.NoError(t, err)
	resp, err := server.CheckStatus(t.Context(), &proto.CheckStatusRequest{
		RepositoryId:      1,
		PullRequestNumber: testhelpers.PR42AsUint64,
	})
	assert.Nil(t, resp)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.Internal, twerr.Code(), "expected error to be a twirp.Internal")
}

func TestCheckStatus_InvalidArgumentErrorForPullRequestNumber(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// PullRequestNumber is too large to fit in a uint32
	pullRequestNumber := uint64(math.MaxUint32) + 1

	resp, err := server.CheckStatus(t.Context(), &proto.CheckStatusRequest{
		RepositoryId:      1,
		PullRequestNumber: pullRequestNumber,
	})
	assert.Nil(t, resp)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.InvalidArgument, twerr.Code(), "expected error to be a twirp.InvalidArgument")
}

func TestCheckStatus_NotFoundErrorWhenCheckJobNotFound(t *testing.T) {
	server := newTestServer(t)

	// Use a repository ID and PR number that don't have a CheckJob
	resp, err := server.CheckStatus(t.Context(), &proto.CheckStatusRequest{
		RepositoryId:      testhelpers.RandomIDForDatabase(),
		PullRequestNumber: testhelpers.PR42AsUint64,
	})
	assert.Nil(t, resp)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.NotFound, twerr.Code(), "expected error to be a twirp.NotFound")
	assert.Contains(t, twerr.Msg(), "no license check job found", "error message should mention check job not found")
}

func TestCheckStatus_StartingStatus(t *testing.T) {
	testCheckStatusWithStatus(t, models.Starting, proto.CheckJobStatus_CHECK_JOB_STATUS_STARTING)
}

func TestCheckStatus_WaitingStatus(t *testing.T) {
	testCheckStatusWithStatus(t, models.Waiting, proto.CheckJobStatus_CHECK_JOB_STATUS_WAITING)
}

func TestCheckStatus_RunningStatus(t *testing.T) {
	testCheckStatusWithStatus(t, models.Running, proto.CheckJobStatus_CHECK_JOB_STATUS_RUNNING)
}

func TestCheckStatus_PassStatus(t *testing.T) {
	testCheckStatusWithStatus(t, models.Pass, proto.CheckJobStatus_CHECK_JOB_STATUS_PASS)
}

func TestCheckStatus_FailStatus(t *testing.T) {
	testCheckStatusWithStatus(t, models.Fail, proto.CheckJobStatus_CHECK_JOB_STATUS_FAIL)
}

func TestCheckStatus_ErrorStatus(t *testing.T) {
	testCheckStatusWithStatus(t, models.Error, proto.CheckJobStatus_CHECK_JOB_STATUS_ERROR)
}

func testCheckStatusWithStatus(t *testing.T, testStatus models.CheckStatus, expectedProtoStatus proto.CheckJobStatus) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()

	// add existing check job
	checkJob, err := server.app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      &enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           "base-sha",
		CommitSHA:         "target-sha",
		ExpectedSnapshots: 5,
		ReceivedSnapshots: 3,
	})
	require.NoError(t, err)

	if testStatus != models.Starting {
		// Update existing check job status to test status
		checkJob.Status = testStatus
		err = server.app.Subsystems.Storage.UpdateCheckJob(t.Context(), checkJob)
		require.NoError(t, err)
	}

	// run CheckStatus
	resp, err := server.CheckStatus(t.Context(), &proto.CheckStatusRequest{
		RepositoryId:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint64,
	})

	require.NoError(t, err)
	assert.NotNil(t, resp)

	expectedResponse := &proto.CheckStatusResponse{
		Id:                checkJob.ID,
		Status:            expectedProtoStatus,
		CheckStartedAt:    resp.CheckStartedAt, // use actual timestamp from response
		RepositoryId:      repoID,
		OrganizationId:    orgID,
		PullRequestId:     pullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint64,
		EnterpriseId:      enterpriseID,
		BaseSha:           "base-sha",
		CommitSha:         "target-sha",
		ExpectedSnapshots: 5,
		ReceivedSnapshots: 3,
		MissingDetectors:  []string{},
	}
	assert.EqualExportedValues(t, expectedResponse, resp, "expected: %v, got: %v", expectedResponse, resp)
}

func TestCheckStatus_ReturnsMissingDetectorsWhileWaiting(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()

	checkJob, err := server.app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      &enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     testhelpers.RandomIDForDatabase(),
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           "base-sha",
		CommitSHA:         "target-sha",
		ExpectedSnapshots: 3,
		ReceivedSnapshots: 1,
		Status:            models.Waiting,
		MissingDetectors:  []string{"detector-one", "detector-two"},
	})
	require.NoError(t, err)

	resp, err := server.CheckStatus(t.Context(), &proto.CheckStatusRequest{
		RepositoryId:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint64,
	})
	require.NoError(t, err)
	require.NotNil(t, resp)

	assert.Equal(t, checkJob.ID, resp.Id)
	assert.Equal(t, proto.CheckJobStatus_CHECK_JOB_STATUS_WAITING, resp.Status)
	assert.Equal(t, []string{"detector-one", "detector-two"}, resp.MissingDetectors)
}

func TestGetAlertsForPullRequest_MissingRepositoryID(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.GetAlertsForPullRequestRequest{
		PullRequestNumber: 42,
	}
	_, err = server.GetAlertsForPullRequest(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirp.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirp.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "repository_id")
}

func TestGetAlertsForPullRequest_MissingPullRequestNumber(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.GetAlertsForPullRequestRequest{
		RepositoryId: 123,
	}
	_, err = server.GetAlertsForPullRequest(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirp.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirp.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "pull_request_number")
}

func TestGetAlertsForPullRequest_ReturnsEmptyForNonExistentPR(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	ctx := t.Context()
	req := &proto.GetAlertsForPullRequestRequest{
		RepositoryId:      999,
		PullRequestNumber: 123,
	}
	resp, err := server.GetAlertsForPullRequest(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	assert.Empty(t, resp.Alerts)
}

func TestGetAlertsForPullRequest_ReturnsAlertsForPR(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	ctx := t.Context()
	repositoryID := uint64(100)
	pullRequestNumber := uint32(42)
	enterpriseID := uint64(10)

	// Create multiple alerts for the same PR
	alert1 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        200,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "4.17.21",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
		Status:                models.AlertStatusOpen,
	}

	alert2 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        200,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "requirements.txt",
		ManifestLineNumber:    5,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_PIP,
		PackageName:           "requests",
		PackageVersion:        "2.28.0",
		SPDXLicenseExpression: "Apache-2.0",
		PullRequestNumber:     &pullRequestNumber,
		Status:                models.AlertStatusClosed,
		Resolution:            models.AlertResolutionExceptionAdded,
	}

	// Create an alert for a different PR (should not be returned)
	differentPR := uint32(99)
	alert3 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        200,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "go.mod",
		ManifestLineNumber:    10,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_GOMOD,
		PackageName:           "github.com/stretchr/testify",
		PackageVersion:        "1.8.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &differentPR,
		Status:                models.AlertStatusOpen,
	}

	created1, err := app.Subsystems.Storage.CreateAlert(ctx, alert1)
	require.NoError(t, err)
	created2, err := app.Subsystems.Storage.CreateAlert(ctx, alert2)
	require.NoError(t, err)
	_, err = app.Subsystems.Storage.CreateAlert(ctx, alert3)
	require.NoError(t, err)

	// Get alerts for the specific PR
	req := &proto.GetAlertsForPullRequestRequest{
		RepositoryId:      repositoryID,
		PullRequestNumber: uint64(pullRequestNumber),
	}
	resp, err := server.GetAlertsForPullRequest(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Alerts, 2, "should return exactly 2 alerts for the PR")

	// Verify the returned alerts match what we created
	alertNumbers := []uint32{resp.Alerts[0].Number, resp.Alerts[1].Number}
	assert.Contains(t, alertNumbers, created1.Number)
	assert.Contains(t, alertNumbers, created2.Number)

	// Verify all alerts have the correct repository and PR number
	for _, alert := range resp.Alerts {
		assert.Equal(t, repositoryID, alert.RepositoryId)
		assert.Equal(t, pullRequestNumber, alert.PullRequestNumber)
	}

	// Verify we have both open and closed alerts
	statuses := []proto.AlertStatus{resp.Alerts[0].Status, resp.Alerts[1].Status}
	assert.Contains(t, statuses, proto.AlertStatus_ALERT_STATUS_OPEN)
	assert.Contains(t, statuses, proto.AlertStatus_ALERT_STATUS_CLOSED)
}

func TestRestartCheckJob_MissingRepositoryID(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.RestartCheckJobRequest{
		PullRequestNumber: 42,
	}
	_, err = server.RestartCheckJob(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirp.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirp.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "repository_id")
}

func TestRestartCheckJob_MissingPullRequestNumber(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.RestartCheckJobRequest{
		RepositoryId: 123,
	}
	_, err = server.RestartCheckJob(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirp.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirp.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "pull_request_number")
}

func TestRestartCheckJob_InvalidPullRequestNumber(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// PullRequestNumber is too large to fit in a uint32
	pullRequestNumber := uint64(math.MaxUint32) + 1

	req := &proto.RestartCheckJobRequest{
		RepositoryId:      123,
		PullRequestNumber: pullRequestNumber,
	}
	_, err = server.RestartCheckJob(t.Context(), req)
	require.Error(t, err)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.InvalidArgument, twerr.Code(), "expected error to be a twirp.InvalidArgument")
}

func TestRestartCheckJob_NotFoundError(t *testing.T) {
	server := newTestServer(t)

	req := &proto.RestartCheckJobRequest{
		RepositoryId:      testhelpers.RandomIDForDatabase(),
		PullRequestNumber: testhelpers.PR42AsUint64,
	}
	_, err := server.RestartCheckJob(t.Context(), req)
	require.Error(t, err)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.NotFound, twerr.Code(), "expected error to be a twirp.NotFound")
	assert.Contains(t, twerr.Msg(), "no license check job found")
}

func TestRestartCheckJob_InternalErrorWhenStorageErrors(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// Close DB to force an unexpected error with GetCheckJob
	err = server.app.Subsystems.Storage.Close()
	require.NoError(t, err)

	req := &proto.RestartCheckJobRequest{
		RepositoryId:      1,
		PullRequestNumber: testhelpers.PR42AsUint64,
	}
	_, err = server.RestartCheckJob(t.Context(), req)
	require.Error(t, err)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.Internal, twerr.Code(), "expected error to be a twirp.Internal")
}

func TestRestartCheckJob_InvalidStatus(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()

	// Create an existing check job (starts in Starting status)
	_, err := server.app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      &enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           "base-sha",
		CommitSHA:         "target-sha",
	})
	require.NoError(t, err)

	// Try to restart a check job that is in Starting status
	req := &proto.RestartCheckJobRequest{
		RepositoryId:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint64,
	}
	_, err = server.RestartCheckJob(t.Context(), req)
	require.Error(t, err)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.InvalidArgument, twerr.Code(), "expected error to be a twirp.InvalidArgument")
	assert.Contains(t, twerr.Msg(), "Pass, Fail, Error, or Waiting")
}

func TestRestartCheckJob_Success(t *testing.T) {
	tests := []struct {
		name   string
		status models.CheckStatus
	}{
		{"Pass", models.Pass},
		{"Fail", models.Fail},
		{"Error", models.Error},
		{"Waiting", models.Waiting},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				server := newTestServer(t)
				orgID := testhelpers.RandomIDForDatabase()
				repoID := testhelpers.RandomIDForDatabase()
				pullRequestID := testhelpers.RandomIDForDatabase()
				enterpriseID := testhelpers.RandomIDForDatabase()

				// Create an existing check job
				checkJob, err := server.app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
					EnterpriseID:      &enterpriseID,
					OrganizationID:    orgID,
					RepositoryID:      repoID,
					PullRequestID:     pullRequestID,
					PullRequestNumber: testhelpers.PR42AsUint32,
					BaseSHA:           "base-sha",
					CommitSHA:         "target-sha",
				})
				require.NoError(t, err)

				// Update to the test status
				checkJob.Status = tt.status
				err = server.app.Subsystems.Storage.UpdateCheckJob(t.Context(), checkJob)
				require.NoError(t, err)

				synctest.Wait()

				req := &proto.RestartCheckJobRequest{
					RepositoryId:      repoID,
					PullRequestNumber: testhelpers.PR42AsUint64,
				}
				resp, err := server.RestartCheckJob(t.Context(), req)
				require.NoError(t, err)
				require.NotNil(t, resp)
				assert.True(t, resp.Success)

				// Wait for the background goroutine spawned by RestartCheckJob to finish
				// before cleanup closes the hydro publisher.
				synctest.Wait()
			})
		})
	}
}

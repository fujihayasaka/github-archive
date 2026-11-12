package twirp

import (
	"errors"
	"math"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"

	ossproto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

func TestCheckRepository_InternalErrorWhenStorageErrors(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// Close DB to force an unexpected error with GetCheckJob
	err = server.app.Subsystems.Storage.Close()
	require.NoError(t, err)
	resp, err := server.CheckRepository(t.Context(), &ossproto.CheckRepositoryRequest{
		EnterpriseId:      0,
		OrganizationId:    0,
		RepositoryId:      1,
		PullRequestNumber: testhelpers.PR42AsUint64,
		BaseSha:           "base-sha",
		CommitSha:         "target-sha",
	})
	assert.Nil(t, resp)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.Internal, twerr.Code(), "expected error to be a twirp.Internal")
}

func TestCheckRepository_InvalidArgumentError(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// PullRequestNumber is too large to fit in a uint32
	pullRequestNumber := uint64(math.MaxUint32) + 1

	// Close DB to force an unexpected error with GetCheckJob
	err = server.app.Subsystems.Storage.Close()
	require.NoError(t, err)
	resp, err := server.CheckRepository(t.Context(), &ossproto.CheckRepositoryRequest{
		EnterpriseId:      0,
		OrganizationId:    0,
		RepositoryId:      1,
		PullRequestNumber: pullRequestNumber,
		BaseSha:           "base-sha",
		CommitSha:         "target-sha",
	})
	assert.Nil(t, resp)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.InvalidArgument, twerr.Code(), "expected error to be a twirp.InvalidArgument")
}

func TestCheckRepository_NewCommitSHA(t *testing.T) {
	server := newTestServer(t)

	req := &ossproto.CheckRepositoryRequest{
		EnterpriseId:      0,
		OrganizationId:    testhelpers.RandomIDForDatabase(),
		RepositoryId:      testhelpers.RandomIDForDatabase(),
		PullRequestId:     testhelpers.RandomIDForDatabase(),
		PullRequestNumber: testhelpers.PR42AsUint64,
		BaseSha:           "base-sha",
		CommitSha:         "target-sha",
		Context:           "distributed",
	}

	resp, err := server.CheckRepository(t.Context(), req)

	require.NoError(t, err)
	assert.NotNil(t, resp)

	expectedResponse := &ossproto.CheckRepositoryResponse{
		Status:  ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PENDING,
		Message: "",
	}
	assert.True(t, proto.Equal(expectedResponse, resp), "expected: %v, got: %v", expectedResponse, resp)
}

func TestCheckRepository_ExistingCommitSHAwithStartingStatus(t *testing.T) {
	testCheckRepositoryExistingCommitSHAwithStatus(t,
		models.Starting,
		ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PENDING,
		"",
	)
}

func TestCheckRepository_ExistingCommitSHAwithWaitingStatus(t *testing.T) {
	testCheckRepositoryExistingCommitSHAwithStatus(t,
		models.Waiting,
		ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PENDING,
		"",
	)
}

func TestCheckRepository_ExistingCommitSHAwithRunningStatus(t *testing.T) {
	testCheckRepositoryExistingCommitSHAwithStatus(t,
		models.Running,
		ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PENDING,
		"",
	)
}

func TestCheckRepository_ExistingCommitSHAwithPassStatus(t *testing.T) {
	testCheckRepositoryExistingCommitSHAwithStatus(t,
		models.Pass,
		ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PASS,
		"",
	)
}

func TestCheckRepository_ExistingCommitSHAwithFailStatus(t *testing.T) {
	testCheckRepositoryExistingCommitSHAwithStatus(t,
		models.Fail,
		ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_FAIL,
		"",
	)
}

func TestCheckRepository_ExistingCommitSHAwithErrorStatus(t *testing.T) {
	testCheckRepositoryExistingCommitSHAwithStatus(t,
		models.Error,
		ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_ERROR,
		"",
	)
}

func testCheckRepositoryExistingCommitSHAwithStatus(t *testing.T, testStatus models.CheckStatus,
	expectedProtoStatus ossproto.RepositoryCheckStatus, expectedMessage string) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()

	// add existing check job
	checkJob, err := server.app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           "base-sha",
		CommitSHA:         "target-sha",
	})
	require.NoError(t, err)

	if testStatus != models.Starting {
		// Update exiting check job status to test status
		checkJob.Status = testStatus
		err = server.app.Subsystems.Storage.UpdateCheckJob(t.Context(), checkJob)
		require.NoError(t, err)
	}

	// run CheckRepository for an existing commit sha
	resp, err := server.CheckRepository(t.Context(), &ossproto.CheckRepositoryRequest{
		OrganizationId:    orgID,
		RepositoryId:      repoID,
		PullRequestId:     pullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint64,
		BaseSha:           "base-sha",
		CommitSha:         "target-sha",
		Context:           "distributed",
	})

	require.NoError(t, err)
	assert.NotNil(t, resp)

	expectedResponse := &ossproto.CheckRepositoryResponse{
		Status:  expectedProtoStatus,
		Message: expectedMessage,
	}
	assert.True(t, proto.Equal(expectedResponse, resp), "expected: %v, got: %v", expectedResponse, resp)
}

func TestStartCheckRepository_HappyPath(t *testing.T) {
	// The tests checking various input problems, error conditions, edge cases, etc.
	// are in repocheck/repocheck_test.go. This test is just to make sure the whole
	// process works end-to-end in a happy path scenario.
	orgID := testhelpers.RandomIDForDatabase()
	repoID := uint64(100) // In seeds, this repo is not expecting any snap
	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, "base-sha", "commit-sha", nil)

	server := &Server{app: app}

	req := &ossproto.CheckRepositoryRequest{
		EnterpriseId:      0,
		OrganizationId:    orgID,
		RepositoryId:      repoID,
		PullRequestId:     testhelpers.RandomIDForDatabase(),
		PullRequestNumber: testhelpers.PR42AsUint64,
		BaseSha:           "basesha",
		CommitSha:         "sha",
		Context:           "distributed",
	}

	// Test startCheckRepository
	server.startCheckRepository(t.Context(), req, testhelpers.PR42AsUint32, nil)

	// This checks that the CheckJob record was created.
	checkJob, err := server.app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.Equal(t, repoID, checkJob.RepositoryID)
	require.Equal(t, testhelpers.PR42AsUint32, checkJob.PullRequestNumber)

	// This checks that the license check ran and passed based on policy and dependency having the same license.
	require.Equal(t, models.Pass.String(), checkJob.Status.String())
}

func TestStartCheckRepository_ForkPRPersistsForkRepositoryID(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := uint64(100)
	forkRepoID := testhelpers.RandomIDForDatabase()
	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, "base-sha", "commit-sha", nil)

	server := &Server{app: app}

	req := &ossproto.CheckRepositoryRequest{
		EnterpriseId:      0,
		OrganizationId:    orgID,
		RepositoryId:      repoID,
		PullRequestId:     testhelpers.RandomIDForDatabase(),
		PullRequestNumber: testhelpers.PR42AsUint64,
		BaseSha:           "basesha",
		CommitSha:         "sha",
		Context:           "distributed",
		ForkRepositoryId:  forkRepoID,
	}

	server.startCheckRepository(t.Context(), req, testhelpers.PR42AsUint32, nil)

	checkJob, err := server.app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.Equal(t, repoID, checkJob.RepositoryID)
	require.NotNil(t, checkJob.ForkRepositoryID)
	assert.Equal(t, forkRepoID, *checkJob.ForkRepositoryID)
	require.Equal(t, models.Pass.String(), checkJob.Status.String())
}

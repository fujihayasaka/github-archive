package repocheck_test

import (
	"fmt"
	"sort"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/eventpublisher"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/remediation"
	"github.com/github/osslicensecompliance/internal/repocheck"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
)

func TestRequest_Validate(t *testing.T) {
	tests := []struct {
		name          string
		request       repocheck.Request
		expectedError error
	}{
		{
			name: "valid request",
			request: repocheck.Request{
				RepositoryID:      123,
				PullRequestNumber: 42,
				OrganizationID:    456,
				CommitSHA:         "abc123",
				BaseSHA:           "def456",
			},
			expectedError: nil,
		},
		{
			name: "missing repository_id",
			request: repocheck.Request{
				RepositoryID:      0,
				PullRequestNumber: 42,
				OrganizationID:    456,
				CommitSHA:         "abc123",
				BaseSHA:           "def456",
			},
			expectedError: repocheck.NewValidationError([]string{"repository_id"}),
		},
		{
			name: "missing pull_request_number",
			request: repocheck.Request{
				RepositoryID:      123,
				PullRequestNumber: 0,
				OrganizationID:    456,
				CommitSHA:         "abc123",
				BaseSHA:           "def456",
			},
			expectedError: repocheck.NewValidationError([]string{"pull_request_number"}),
		},
		{
			name: "missing organization_id",
			request: repocheck.Request{
				RepositoryID:      123,
				PullRequestNumber: 42,
				OrganizationID:    0,
				CommitSHA:         "abc123",
				BaseSHA:           "def456",
			},
			expectedError: repocheck.NewValidationError([]string{"organization_id"}),
		},
		{
			name: "missing commit_sha",
			request: repocheck.Request{
				RepositoryID:      123,
				PullRequestNumber: 42,
				OrganizationID:    456,
				CommitSHA:         "",
				BaseSHA:           "def456",
			},
			expectedError: repocheck.NewValidationError([]string{"commit_sha"}),
		},
		{
			name: "missing base_sha",
			request: repocheck.Request{
				RepositoryID:      123,
				PullRequestNumber: 42,
				OrganizationID:    456,
				CommitSHA:         "abc123",
				BaseSHA:           "",
			},
			expectedError: repocheck.NewValidationError([]string{"base_sha"}),
		},
		{
			name: "missing multiple fields",
			request: repocheck.Request{
				RepositoryID:      0,
				PullRequestNumber: 0,
				OrganizationID:    456,
				CommitSHA:         "",
				BaseSHA:           "def456",
			},
			expectedError: repocheck.NewValidationError([]string{"repository_id", "pull_request_number", "commit_sha"}),
		},
		{
			name: "missing all fields",
			request: repocheck.Request{
				RepositoryID:      0,
				PullRequestNumber: 0,
				OrganizationID:    0,
				CommitSHA:         "",
				BaseSHA:           "",
			},
			expectedError: repocheck.NewValidationError([]string{"repository_id", "pull_request_number", "organization_id", "commit_sha", "base_sha"}),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.request.Validate()

			if tt.expectedError == nil {
				assert.NoError(t, err)
			} else {
				require.Error(t, err)

				var actualValidationErr *repocheck.ValidationError
				require.ErrorAs(t, err, &actualValidationErr)

				var expectedValidationErr *repocheck.ValidationError
				require.ErrorAs(t, tt.expectedError, &expectedValidationErr)

				assert.Equal(t, expectedValidationErr.MissingFields, actualValidationErr.MissingFields)
				assert.Equal(t, tt.expectedError.Error(), err.Error())
			}
		})
	}
}

func TestStart_ErrFromNewCheckJob(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)

	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()

	// Close DB to force an unexpected error with CreateCheckJob
	err = app.Subsystems.Storage.Close()
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
	// Verify the underlying storage error is preserved in the error chain
	assert.Contains(t, err.Error(), "database is closed")
}

func TestStart_CheckJobNilButAlreadyExists(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	baseSHA := "basesha"
	commitSHA := "sha"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)

	// Create first check job
	firstCheckJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		Status:            models.Starting,
	})
	require.NoError(t, err)
	require.Equal(t, models.Starting, firstCheckJob.Status)

	checkRequest := &repocheck.Request{
		EnterpriseID:      0,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		Context:           "distributed",
	}

	// Try to run check repository without passing the existing check job (checkJob = nil)
	// This should fail with ErrCheckAlreadyExists because a job already exists for this repo/PR
	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.Start(t.Context(), nil, checkRequest)

	require.Error(t, err)
	require.ErrorIs(t, err, repocheck.ErrCheckJobCreation)
	require.ErrorIs(t, err, storage.ErrCheckAlreadyExists)
}

func TestStart_UpdateSnapshotsForExistingCheckJob(t *testing.T) {
	repoID := uint64(200)     // Use repo ID that exists in seeds
	commitSHA := "target-sha" // Use commit SHA from seeds
	baseSHA := "base-sha"     // Use base SHA from seeds

	dsConfig, err := loadDiffStatusNullConfig()
	require.NoError(t, err)
	require.NotNil(t, dsConfig)

	logger := log.NewNullLogger()
	nullConfig := &application.NullConfig{DiffStatusConfig: *dsConfig}
	app, err := application.NewNullApplication(nullConfig, logger)
	require.NoError(t, err)
	require.NotNil(t, app)

	orgID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	pullRequestNum := testhelpers.PR42AsUint32

	// add existing check job
	originalCheckJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: pullRequestNum,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		ExpectedSnapshots: 5, // uses same base_count as the seed
		ReceivedSnapshots: 0, // uses commit_count=0 to simulate no snapshots received yet
		Status:            models.Waiting,
	})
	require.NoError(t, err)
	require.Equal(t, commitSHA, originalCheckJob.CommitSHA)
	require.Equal(t, models.Waiting.String(), originalCheckJob.Status.String())
	require.Equal(t, uint32(5), originalCheckJob.ExpectedSnapshots)
	require.Equal(t, uint32(0), originalCheckJob.ReceivedSnapshots)

	checkRequest := &repocheck.Request{
		EnterpriseID:      0,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: pullRequestNum,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
	}

	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.Start(t.Context(), originalCheckJob, checkRequest)
	require.NoError(t, err)

	// The seed for 200:base-sha...target-sha will set the snapshot base_count=5 and commit_count=2
	// and simulates an increase in the number of received snapshots, but still waiting for more.
	updatedCheckJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, pullRequestNum)
	require.NoError(t, err)
	assert.Equal(t, models.Waiting.String(), updatedCheckJob.Status.String())
	assert.Equal(t, uint32(5), updatedCheckJob.ExpectedSnapshots)
	assert.Equal(t, uint32(2), updatedCheckJob.ReceivedSnapshots)
}

func TestStart_CommitSHAChanged(t *testing.T) {
	repoID := uint64(200)     // Use repo ID that exists in seeds
	commitSHA := "target-sha" // Use commit SHA from seeds
	baseSHA := "base-sha"     // Use base SHA from seeds

	newCommitSHA := "new-target-sha"

	dsConfig, err := loadDiffStatusNullConfig()
	require.NoError(t, err)
	require.NotNil(t, dsConfig)

	logger := log.NewNullLogger()
	nullConfig := &application.NullConfig{DiffStatusConfig: *dsConfig}
	app, err := application.NewNullApplication(nullConfig, logger)
	require.NoError(t, err)
	require.NotNil(t, app)

	orgID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	pullRequestNum := testhelpers.PR42AsUint32

	// add existing check job
	originalCheckJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: pullRequestNum,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		ExpectedSnapshots: 5,               // uses same base_count as the seed
		ReceivedSnapshots: 5,               // uses commit_count=5 to simulate all snapshots received
		Status:            models.Starting, // Using Starting here to test for update to Waiting after processing.
	})
	require.NoError(t, err)
	require.Equal(t, commitSHA, originalCheckJob.CommitSHA)
	require.Equal(t, models.Starting.String(), originalCheckJob.Status.String())
	require.Equal(t, uint32(5), originalCheckJob.ExpectedSnapshots)
	require.Equal(t, uint32(5), originalCheckJob.ReceivedSnapshots)

	checkRequest := &repocheck.Request{
		EnterpriseID:      0,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: pullRequestNum,
		BaseSHA:           baseSHA,
		CommitSHA:         newCommitSHA,
	}

	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.Start(t.Context(), originalCheckJob, checkRequest)
	require.NoError(t, err)

	// The seed for 200:base-sha...new-target-sha will set the snapshot base_count=5 and commit_count=0
	// and simulates a restart where no snapshots have been received yet, but are expected.
	updatedCheckJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, pullRequestNum)
	require.NoError(t, err)
	assert.Equal(t, newCommitSHA, updatedCheckJob.CommitSHA)
	assert.Equal(t, uint32(5), updatedCheckJob.ExpectedSnapshots)
	assert.Equal(t, uint32(0), updatedCheckJob.ReceivedSnapshots)
	assert.Equal(t, models.Waiting.String(), updatedCheckJob.Status.String())
}

func TestStart_BaseSHAChanged(t *testing.T) {
	repoID := uint64(200)     // Use repo ID that exists in seeds
	commitSHA := "target-sha" // Use commit SHA from seeds
	baseSHA := "base-sha"     // Use base SHA from seeds

	newBaseSHA := "new-base-sha"

	dsConfig, err := loadDiffStatusNullConfig()
	require.NoError(t, err)
	require.NotNil(t, dsConfig)

	logger := log.NewNullLogger()
	nullConfig := &application.NullConfig{DiffStatusConfig: *dsConfig}
	app, err := application.NewNullApplication(nullConfig, logger)
	require.NoError(t, err)
	require.NotNil(t, app)

	orgID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	pullRequestNum := testhelpers.PR42AsUint32

	// add existing check job
	originalCheckJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: pullRequestNum,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		ExpectedSnapshots: 5,               // uses same base_count as the seed
		ReceivedSnapshots: 3,               // uses commit_count=3 to simulate some snapshots received
		Status:            models.Starting, // Using Starting here to test for update to Waiting after processing.
	})
	require.NoError(t, err)
	require.Equal(t, commitSHA, originalCheckJob.CommitSHA)
	require.Equal(t, models.Starting.String(), originalCheckJob.Status.String())
	require.Equal(t, uint32(5), originalCheckJob.ExpectedSnapshots)
	require.Equal(t, uint32(3), originalCheckJob.ReceivedSnapshots)

	checkRequest := &repocheck.Request{
		EnterpriseID:      0,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: pullRequestNum,
		BaseSHA:           newBaseSHA,
		CommitSHA:         commitSHA,
	}

	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.Start(t.Context(), originalCheckJob, checkRequest)
	require.NoError(t, err)

	// The seed for 200:new-base-sha...target-sha will set the snapshot base_count=6 and commit_count=0
	// and simulates a restart where no snapshots have been received yet, and there is an additional
	// snapshot expected based on the change to the base.
	updatedCheckJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, pullRequestNum)
	require.NoError(t, err)
	assert.Equal(t, newBaseSHA, updatedCheckJob.BaseSHA)
	assert.Equal(t, models.Waiting.String(), updatedCheckJob.Status.String())
	assert.Equal(t, uint32(6), updatedCheckJob.ExpectedSnapshots)
	assert.Equal(t, uint32(0), updatedCheckJob.ReceivedSnapshots)
}

func TestExecuteJob_CheckRepositoryPass(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	baseSHA := "basesha"
	commitSHA := "sha"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)

	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		Status:            models.Starting,
	})
	require.NoError(t, err)
	require.Equal(t, models.Starting, checkJob.Status)

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

	resp, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)

	assert.True(t, (resp.Status == models.Pass), "expected status to be Pass, got: %s", resp.Status)
}

func TestExecuteJob_CheckRepositoryFailLicense(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	baseSHA := "basesha"
	commitSHA := "sha"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "MIT", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)

	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		Status:            models.Starting,
	})
	require.NoError(t, err)
	require.Equal(t, models.Starting, checkJob.Status)

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

	resp, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)

	assert.True(t, (resp.Status == models.Fail), "expected status to be Fail, got: %s", resp.Status)
}

func TestExecuteJob_CheckRepositoryFailContext(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	baseSHA := "basesha"
	commitSHA := "sha"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "MIT", testhelpers.SubsetContexts, baseSHA, commitSHA, nil)

	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		Status:            models.Starting,
	})
	require.NoError(t, err)
	require.Equal(t, models.Starting, checkJob.Status)

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

	resp, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)

	assert.True(t, (resp.Status == models.Fail), "expected status to be Fail, got: %s", resp.Status)
}

func TestExecuteJob_CheckRepositoryFailError(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	baseSHA := "basesha"
	commitSHA := "sha"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "NON-EXISTENT-LICENSE", "MIT", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)

	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		Status:            models.Starting,
	})
	require.NoError(t, err)
	require.Equal(t, models.Starting, checkJob.Status)

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

	resp, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)

	assert.True(t, (resp.Status == models.Fail), "expected status to be Fail, got: %s", resp.Status)
}

func TestExecuteJob_NoCompletePolicy(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)

	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()

	// No policy created — GetCompletePolicyWithVersion should return ErrNotFound

	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           "baseSHA",
		CommitSHA:         "sha",
		Status:            models.Starting,
	})
	require.NoError(t, err)

	checkRequest := &repocheck.Request{
		EnterpriseID:      1,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		CommitSHA:         "sha",
		BaseSHA:           "baseSHA",
	}

	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.ExecuteJob(t.Context(), checkJob, checkRequest)
	require.Error(t, err)
	require.ErrorIs(t, err, repocheck.ErrPolicyNotFound)
}

func TestExecuteJob_CheckRepositoryPassWithRepoPolicy(t *testing.T) {
	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()
	baseSHA := "basesha"
	commitSHA := "sha"

	dpConfig := dependencies.NullConfig{
		GetSnapshotsDiffResponses: map[string]*dg.GetSnapshotsDiffResponse{
			fmt.Sprintf("%d:%s:%s", repoID, baseSHA, commitSHA): {
				ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
					{
						Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
						FilePath: "./gemfile.lock",
						Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
							{
								Name:          "gem-lockfile",
								TargetVersion: "1.0.1",
								ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
								License:       "BSD-3-Clause",
							},
						},
					},
				},
			},
		},
	}
	app, err := application.NewNullApplication(&application.NullConfig{DependenciesConfig: dpConfig}, log.NewNullLogger())
	require.NoError(t, err)

	repoPolicy := &proto.RepositoryPolicy{
		RepositoryId: repoID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "BSD-3-Clause", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	}
	_, err = app.Subsystems.Storage.CreateRepositoryPolicy(t.Context(), repoPolicy)
	require.NoError(t, err)

	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		Status:            models.Starting,
	})
	require.NoError(t, err)

	checkRequest := &repocheck.Request{
		EnterpriseID:      1,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
		Context:           "distributed",
	}

	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.ExecuteJob(t.Context(), checkJob, checkRequest)
	require.NoError(t, err)

	resp, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)

	assert.True(t, (resp.Status == models.Pass), "expected status to be Pass, got: %s", resp.Status)
}

func TestExecuteJob_NoAlertUpdateForDifferentCommitSHA(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)

	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	prNumber := uint32(42)
	existingCommitSHA := "old-commit123"
	newCommitSHA := "new-commit456"
	baseSHA := "base456"

	// Create a policy that allows BSD-3-Clause but not MIT
	policy := &proto.OrganizationPolicy{
		OrganizationId: orgID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "BSD-3-Clause", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	}
	_, err = app.Subsystems.Storage.CreateOrganizationPolicy(t.Context(), policy)
	require.NoError(t, err)

	// Create an existing check job with a different commit SHA
	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		RepositoryID:      repoID,
		OrganizationID:    orgID,
		EnterpriseID:      &enterpriseID,
		PullRequestID:     testhelpers.RandomIDForDatabase(),
		PullRequestNumber: prNumber,
		BaseSHA:           baseSHA,
		CommitSHA:         newCommitSHA, // Different from what we'll check
		Status:            models.Pass,
	})
	require.NoError(t, err)

	// Create an existing alert to verify it's NOT closed when commits don't match
	existingAlert := models.Alert{
		RepositoryID:          repoID,
		OrganizationID:        orgID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "test-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &prNumber,
	}
	_, err = app.Subsystems.Storage.CreateAlert(t.Context(), existingAlert)
	require.NoError(t, err)

	checkRequest := &repocheck.Request{
		EnterpriseID:      enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		Context:           "distributed",
		CommitSHA:         existingCommitSHA, // Stale commit SHA
		BaseSHA:           baseSHA,
		PullRequestNumber: prNumber,
	}

	// Run ExecuteJob — the SHA mismatch in checkWithPolicy should prevent alert updates
	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.ExecuteJob(t.Context(), checkJob, checkRequest)
	require.NoError(t, err)

	// Verify the existing alert is still open because the commit SHAs didn't match
	openAlertsAfter, err := app.Subsystems.Storage.GetOpenAlerts(t.Context(), repoID, &prNumber)
	require.NoError(t, err)
	assert.Equal(t, 1, len(openAlertsAfter), "Alert should still be open since commits don't match")
}

func TestUpdateAlerts(t *testing.T) {
	tp := testpublisher.NewTestPublisher(t)
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	app.Subsystems.EventPublisher = tp.Publisher

	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	prNumber := uint32(42)

	// Create test data - packages that have failed policy evaluation
	failedPackage1 := models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		Version:        "4.17.21",
		License:        "GPL-3.0",
		Manifests:      []string{"package.json", "package-lock.json"},
	}

	failedPackage2 := models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_PIP,
		Name:           "requests",
		Version:        "2.28.1",
		License:        "Apache-2.0",
		Manifests:      []string{"requirements.txt"},
	}

	results := evaluator.RepositoryResults{
		SuccessCount: 2,
		FailureCount: 2,
		ErrorCount:   0,
		LastError:    nil,
		Failures: []evaluator.PackageFailure{
			{
				Package: failedPackage1,
				Reason:  evaluator.LicenseNotAllowed,
				Level:   proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
			},
			{
				Package: failedPackage2,
				Reason:  evaluator.PackageBlocked,
				Level:   proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
			},
		},
	}

	checkRequest := &repocheck.Request{
		EnterpriseID:      enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		Context:           "distributed",
		CommitSHA:         "commit123",
		BaseSHA:           "base456",
		PullRequestNumber: prNumber,
	}

	checker := repocheck.NewChecker(app, app.StatsClient)
	rg := "remediation-guidance"
	err = checker.UpdateAlerts(t.Context(), results, checkRequest, rg)
	require.NoError(t, err)

	openAlerts, err := app.Subsystems.Storage.GetOpenAlerts(t.Context(), repoID, &prNumber)
	require.NoError(t, err)
	require.Equal(t, 2, len(openAlerts), "Should have 2 open alert groups")

	assertPRLicenseCheckCompleteEventPublished(t, tp, openAlerts, repoID, checkRequest.PullRequestID, prNumber, checkRequest.CommitSHA, checkRequest.BaseSHA, rg)
}

func TestUpdateAlerts_ClosesResolvedAlerts(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)

	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	prNumber := uint32(42)

	// First, create some existing alerts by simulating a previous policy check with failures
	failedPackage1 := models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		Version:        "4.17.21",
		License:        "GPL-3.0",
		Manifests:      []string{"package.json"},
		PackageRepoNWO: "lodash/lodash",
	}

	failedPackage2 := models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_PIP,
		Name:           "requests",
		Version:        "2.28.1",
		License:        "Apache-2.0",
		Manifests:      []string{"requirements.txt"},
		PackageRepoNWO: "psf/requests",
	}

	initialResults := evaluator.RepositoryResults{
		SuccessCount: 0,
		FailureCount: 2,
		ErrorCount:   0,
		LastError:    nil,
		Failures: []evaluator.PackageFailure{
			{
				Package: failedPackage1,
				Reason:  evaluator.LicenseNotAllowed,
				Level:   proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
			},
			{
				Package: failedPackage2,
				Reason:  evaluator.PackageBlocked,
				Level:   proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
			},
		},
	}

	checkRequest := &repocheck.Request{
		EnterpriseID:      enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		Context:           "distributed",
		CommitSHA:         "commit123",
		BaseSHA:           "base456",
		PullRequestNumber: prNumber,
	}

	// Create initial alerts
	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.UpdateAlerts(t.Context(), initialResults, checkRequest, "")
	require.NoError(t, err)

	// Verify alerts were created
	openAlerts, err := app.Subsystems.Storage.GetOpenAlerts(t.Context(), repoID, &prNumber)
	require.NoError(t, err)
	require.Equal(t, 2, len(openAlerts), "Should have 2 open alert groups")

	// Now simulate a new policy check where only one package is still failing
	// (lodash is fixed, but requests still fails)
	updatedResults := evaluator.RepositoryResults{
		SuccessCount: 1, // lodash is now passing
		FailureCount: 1, // only requests is still failing
		ErrorCount:   0,
		LastError:    nil,
		Failures: []evaluator.PackageFailure{
			{
				Package: failedPackage2, // only requests is still failing
				Reason:  evaluator.PackageBlocked,
				Level:   proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
			},
		},
	}

	// Set publisher here as only want to assert of final call of UpdateAlertsForRepository
	tp := testpublisher.NewTestPublisher(t)
	app.Subsystems.EventPublisher = tp.Publisher
	checker = repocheck.NewChecker(app, app.StatsClient)
	// Update alerts - this should close the lodash alert and keep the requests alert open
	err = checker.UpdateAlerts(t.Context(), updatedResults, checkRequest, "")
	require.NoError(t, err)

	// Verify the lodash alert was closed and requests alert remains open
	openAlertsAfterUpdate, err := app.Subsystems.Storage.GetOpenAlerts(t.Context(), repoID, &prNumber)
	require.NoError(t, err)
	require.Equal(t, 1, len(openAlertsAfterUpdate), "Should have only 1 open alert group remaining")

	// Verify the remaining alert is for requests
	requestsKey := storage.CreatePackageKey("pip", "requests", "Apache-2.0")
	requestsAlerts, exists := openAlertsAfterUpdate[requestsKey]
	require.True(t, exists, "Requests alert should still be open")
	require.Equal(t, 1, len(requestsAlerts), "Should have 1 requests alert")

	// Verify the lodash alert no longer exists in open alerts
	lodashKey := storage.CreatePackageKey("npm", "lodash", "GPL-3.0")
	_, lodashExists := openAlertsAfterUpdate[lodashKey]
	require.False(t, lodashExists, "Lodash alert should have been closed")

	// Verify the lodash alert was actually closed by checking its status directly
	lodashAlert, err := app.Subsystems.Storage.GetAlert(t.Context(), repoID, 1) // First alert created
	require.NoError(t, err)
	require.NotNil(t, lodashAlert)
	require.Equal(t, models.AlertStatusClosed, lodashAlert.Status, "Lodash alert should be closed")
	require.Equal(t, models.AlertResolutionOutdated, lodashAlert.Resolution, "Alert should be closed with Outdated resolution")
	require.Equal(t, "lodash/lodash", lodashAlert.PackageRepoNWO, "Alert should include PackageRepoNWO from package")

	// Verify a closed event was created for lodash
	lodashEvent, err := app.Subsystems.Storage.GetAlertEvent(t.Context(), lodashAlert.ID, models.EventClosed)
	require.NoError(t, err)
	require.NotNil(t, lodashEvent)

	// Verify LicenseComplianceAlertStatusChanged event is published first
	tp.AssertMessageTopic(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged")

	// Ensure only the current open alerts are published in the PullRequestLicenseCheckComplete event
	assertPRLicenseCheckCompleteEventPublished(t, tp, openAlertsAfterUpdate, repoID, checkRequest.PullRequestID, prNumber, checkRequest.CommitSHA, checkRequest.BaseSHA, "")
}

func TestUpdateAlerts_ClosesAllAlertsWhenNoFailures(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)

	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	prNumber := uint32(42)

	// Create initial alerts
	failedPackage := models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		Version:        "4.17.21",
		License:        "GPL-3.0",
		Manifests:      []string{"package.json"},
	}

	initialResults := evaluator.RepositoryResults{
		SuccessCount: 0,
		FailureCount: 1,
		ErrorCount:   0,
		LastError:    nil,
		Failures: []evaluator.PackageFailure{
			{
				Package: failedPackage,
				Reason:  evaluator.LicenseNotAllowed,
				Level:   proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
			},
		},
	}

	checkRequest := &repocheck.Request{
		EnterpriseID:      enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		Context:           "distributed",
		CommitSHA:         "commit123",
		BaseSHA:           "base456",
		PullRequestNumber: prNumber,
	}

	// Create initial alert
	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.UpdateAlerts(t.Context(), initialResults, checkRequest, "")
	require.NoError(t, err)

	// Verify alert was created
	openAlerts, err := app.Subsystems.Storage.GetOpenAlerts(t.Context(), repoID, &prNumber)
	require.NoError(t, err)
	require.Equal(t, 1, len(openAlerts), "Should have 1 open alert group")

	// Now simulate a policy check with no failures (all packages pass)
	allPassingResults := evaluator.RepositoryResults{
		SuccessCount: 1, // All packages now pass
		FailureCount: 0, // No failures
		ErrorCount:   0,
		LastError:    nil,
		Failures:     []evaluator.PackageFailure{}, // No failures
	}

	tp := testpublisher.NewTestPublisher(t)
	app.Subsystems.EventPublisher = tp.Publisher
	checker = repocheck.NewChecker(app, app.StatsClient)
	// Update alerts - this should close all alerts
	err = checker.UpdateAlerts(t.Context(), allPassingResults, checkRequest, "")
	require.NoError(t, err)

	// Verify all alerts were closed
	openAlertsAfterUpdate, err := app.Subsystems.Storage.GetOpenAlerts(t.Context(), repoID, &prNumber)
	require.NoError(t, err)
	require.Equal(t, 0, len(openAlertsAfterUpdate), "Should have no open alerts remaining")

	// Verify the alert was actually closed
	closedAlert, err := app.Subsystems.Storage.GetAlert(t.Context(), repoID, 1)
	require.NoError(t, err)
	require.NotNil(t, closedAlert)
	require.Equal(t, models.AlertStatusClosed, closedAlert.Status, "Alert should be closed")
	require.Equal(t, models.AlertResolutionOutdated, closedAlert.Resolution, "Alert should be closed with Outdated resolution")

	// Skip the LicenseComplianceAlertStatusChanged event that's published first
	tp.SkipMessage(t)

	// Ensure only the current open alerts are published in the event
	assertPRLicenseCheckCompleteEventPublished(t, tp, openAlertsAfterUpdate, repoID, checkRequest.PullRequestID, prNumber, checkRequest.CommitSHA, checkRequest.BaseSHA, "")
}

func TestUpdateAlerts_PublishesEventWithNoOpenAlerts(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)

	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	prNumber := uint32(42)

	policy := &proto.OrganizationPolicy{
		OrganizationId: orgID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts},
				{SpdxId: "Apache-2.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	}
	_, err = app.Subsystems.Storage.CreateOrganizationPolicy(t.Context(), policy)
	require.NoError(t, err)

	checkRequest := &repocheck.Request{
		EnterpriseID:      enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     testhelpers.RandomIDForDatabase(),
		Context:           "distributed",
		CommitSHA:         "commit123",
		BaseSHA:           "base456",
		PullRequestNumber: prNumber,
	}

	// Simulate a policy check where all packages pass (no alerts created)
	allPassingResults := evaluator.RepositoryResults{
		SuccessCount: 2, // All packages pass
		FailureCount: 0, // No failures
		ErrorCount:   0,
		LastError:    nil,
		Failures:     []evaluator.PackageFailure{}, // No failures
	}

	tp := testpublisher.NewTestPublisher(t)
	app.Subsystems.EventPublisher = tp.Publisher

	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.UpdateAlerts(t.Context(), allPassingResults, checkRequest, "")
	require.NoError(t, err)

	// Verify no alerts were created
	openAlerts, err := app.Subsystems.Storage.GetOpenAlerts(t.Context(), repoID, &prNumber)
	require.NoError(t, err)
	require.Equal(t, 0, len(openAlerts), "Should have no open alerts")

	// Ensure an event is still published even with no open alerts
	assertPRLicenseCheckCompleteEventPublished(t, tp, openAlerts, repoID, checkRequest.PullRequestID, prNumber, checkRequest.CommitSHA, checkRequest.BaseSHA, "")
}

func TestUpdateAlerts_PreventsDuplicateAlerts(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)

	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	prNumber := uint32(42)

	// Create a package that will fail policy evaluation
	failedPackage := models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		Version:        "4.17.21",
		License:        "GPL-3.0",
		Manifests:      []string{"package.json"},
	}

	results := evaluator.RepositoryResults{
		SuccessCount: 0,
		FailureCount: 1,
		ErrorCount:   0,
		LastError:    nil,
		Failures: []evaluator.PackageFailure{
			{
				Package: failedPackage,
				Reason:  evaluator.LicenseNotAllowed,
				Level:   proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
			},
		},
	}

	checkRequest := &repocheck.Request{
		EnterpriseID:      enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		Context:           "distributed",
		CommitSHA:         "commit123",
		BaseSHA:           "base456",
		PullRequestNumber: prNumber,
	}

	// First policy evaluation - create the initial alert
	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.UpdateAlerts(t.Context(), results, checkRequest, "")
	require.NoError(t, err)

	// Verify the alert was created
	openAlertsAfterFirst, err := app.Subsystems.Storage.GetOpenAlerts(t.Context(), repoID, &prNumber)
	require.NoError(t, err)
	require.Equal(t, 1, len(openAlertsAfterFirst), "Should have 1 open alert group after first evaluation")

	// Pretend a review was requested. This alert is still open!
	lodashKey := storage.CreatePackageKey("npm", "lodash", "GPL-3.0")
	openAlert := openAlertsAfterFirst[lodashKey][0]
	userID := uint64(12345)
	ctx := t.Context()
	err = remediation.RequestAlertClosure(ctx, app, openAlert, userID, "Please approve.", nil)
	require.NoError(t, err)

	lodashAlerts, exists := openAlertsAfterFirst[lodashKey]
	require.True(t, exists, "Lodash alert should exist")
	require.Equal(t, 1, len(lodashAlerts), "Should have exactly 1 lodash alert")
	firstAlertNumber := lodashAlerts[0].Number

	tp := testpublisher.NewTestPublisher(t)
	app.Subsystems.EventPublisher = tp.Publisher
	checker = repocheck.NewChecker(app, app.StatsClient)
	// Second policy evaluation with the exact same failure - should not create duplicate
	err = checker.UpdateAlerts(t.Context(), results, checkRequest, "")
	require.NoError(t, err)

	// Verify no duplicate alert was created
	openAlertsAfterSecond, err := app.Subsystems.Storage.GetOpenAlerts(t.Context(), repoID, &prNumber)
	require.NoError(t, err)
	require.Equal(t, 1, len(openAlertsAfterSecond), "Should still have only 1 open alert group after second evaluation")

	lodashAlertsAfterSecond, exists := openAlertsAfterSecond[lodashKey]
	require.True(t, exists, "Lodash alert should still exist")
	require.Equal(t, 1, len(lodashAlertsAfterSecond), "Should still have exactly 1 lodash alert (no duplicates)")
	require.Equal(t, firstAlertNumber, lodashAlertsAfterSecond[0].Number, "Alert number should be the same (no new alert created)")

	// Ensure only the current open alerts are published in the event
	assertPRLicenseCheckCompleteEventPublished(t, tp, openAlertsAfterSecond, repoID, checkRequest.PullRequestID, prNumber, checkRequest.CommitSHA, checkRequest.BaseSHA, "")
}

func TestUpdateAlerts_PublishesStatusChangedEventForOutdatedAlerts(t *testing.T) {
	tests := []struct {
		name               string
		alertStatus        models.AlertStatus
		shouldUpdateStatus bool
		alertEvent         models.AlertEventType
		previousStatus     entities.AlertStatus
	}{
		{
			name:               "alert with ReviewRequested status publishes event",
			alertStatus:        models.AlertStatusReviewRequested,
			shouldUpdateStatus: true,
			alertEvent:         models.EventReviewRequested,
			previousStatus:     entities.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED,
		},
		{
			name:               "alert with Open status publishes event",
			alertStatus:        models.AlertStatusOpen,
			shouldUpdateStatus: false,
			previousStatus:     entities.AlertStatus_ALERT_STATUS_OPEN,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
			require.NoError(t, err)

			tp := testpublisher.NewTestPublisher(t)
			app.Subsystems.EventPublisher = tp.Publisher
			checker := repocheck.NewChecker(app, app.StatsClient)

			repoID := testhelpers.RandomIDForDatabase()
			orgID := testhelpers.RandomIDForDatabase()
			prID := testhelpers.RandomIDForDatabase()
			enterpriseID := testhelpers.RandomIDForDatabase()
			prNumber := uint32(42)

			// Create alert
			alert := models.Alert{
				RepositoryID:          repoID,
				OrganizationID:        orgID,
				EnterpriseID:          &enterpriseID,
				PullRequestNumber:     &prNumber,
				ManifestName:          "package.json",
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "test-package",
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: "GPL-3.0",
			}

			createdAlert, err := app.Subsystems.Storage.CreateAlert(t.Context(), alert)
			require.NoError(t, err)

			// Update alert status if needed (alerts start as Open by default)
			if tt.shouldUpdateStatus {
				if tt.alertStatus == models.AlertStatusReviewRequested {
					tx := app.Subsystems.Storage.NewTransactor(t.Context())
					createdAlert.Status = tt.alertStatus
					tx.AddStep(storage.NewTransitionAlertStep(createdAlert, models.AlertStatusOpen))
					err = tx.Execute()
					require.NoError(t, err)
					// Note: we would _generally_ want to use the code below to invoke the usual way in which an
					// alert goes from open to review requested. However, the function below publishes an event, which
					// confuses the test. The test is expecting a close event and not a review requested event.
					// err = remediation.RequestAlertClosure(t.Context(), app, createdAlert, uint64(12345), "Please review.", nil)
				} else {
					require.Fail(t, "Unknown alert status", "Status is: %d", tt.alertStatus)
				}
			}

			createdAlert, err = app.Subsystems.Storage.GetAlert(t.Context(), repoID, createdAlert.Number)
			require.NoError(t, err)
			require.NotNil(t, createdAlert)

			// Simulate a policy check where all packages pass which should
			// close test-package alert and publish status changed event
			checkRequest := &repocheck.Request{
				EnterpriseID:      enterpriseID,
				OrganizationID:    orgID,
				RepositoryID:      repoID,
				PullRequestID:     prID,
				Context:           "distributed",
				CommitSHA:         "commit123",
				BaseSHA:           "base456",
				PullRequestNumber: prNumber,
			}

			allPassingResults := evaluator.RepositoryResults{
				SuccessCount: 2, // All packages pass
				FailureCount: 0, // No failures
				ErrorCount:   0,
				LastError:    nil,
				Failures:     []evaluator.PackageFailure{}, // No failures
			}

			err = checker.UpdateAlerts(t.Context(), allPassingResults, checkRequest, "")
			require.NoError(t, err)

			assertAlertStatusChangedEventPublished(t, createdAlert, tt.previousStatus, int64(prID), tp)
		})
	}
}

// assertPRLicenseCheckCompleteEventPublished is a helper function that builds the expected
// PullRequestLicenseCheckComplete proto from the given alerts and asserts it was published.
func assertPRLicenseCheckCompleteEventPublished(t *testing.T,
	tp *testpublisher.TestPublisher,
	openAlertsMap map[string][]*models.Alert,
	repoID,
	prID uint64,
	prNumber uint32,
	commitSHA,
	baseSHA,
	remediationGuidance string,
) {
	t.Helper()

	var alertSlice []*models.Alert
	for _, alerts := range openAlertsMap {
		alertSlice = append(alertSlice, alerts...)
	}

	// Sort alerts by ID to ensure deterministic order for testing
	sort.Slice(alertSlice, func(i, j int) bool {
		return alertSlice[i].ID < alertSlice[j].ID
	})

	expectedProto := &dependencygraphv1.PullRequestLicenseCheckComplete{
		PullRequestId:       int64(prID),     // #nosec G115
		PullRequestNumber:   int32(prNumber), // #nosec G115
		CommitSha:           commitSHA,
		BaseSha:             baseSHA,
		RepositoryId:        int64(repoID), // #nosec G115
		RemediationGuidance: remediationGuidance,
		OpenLicenseAlerts:   []*entities.LicenseComplianceAlert{},
	}

	for _, alert := range alertSlice {
		var enterpriseID *wrapperspb.Int64Value
		if alert.EnterpriseID != nil {
			enterpriseID = &wrapperspb.Int64Value{Value: int64(*alert.EnterpriseID)} // #nosec G115
		}
		expectedProto.OpenLicenseAlerts = append(expectedProto.OpenLicenseAlerts, &entities.LicenseComplianceAlert{
			AlertId:               int64(alert.ID),     // #nosec G115
			AlertNumber:           int32(alert.Number), // #nosec G115
			CreatedAt:             timestamppb.New(alert.CreatedAt),
			RepositoryId:          int64(alert.RepositoryID),   // #nosec G115
			OrganizationId:        int64(alert.OrganizationID), // #nosec G115
			EnterpriseId:          enterpriseID,
			PullRequestNumber:     int32(prNumber), // #nosec G115
			PullRequestId:         int64(prID),     // #nosec G115
			ManifestName:          alert.ManifestName,
			PackageManager:        eventpublisher.ModelToProtoPackageManager(alert.PackageEcosystem),
			PackageName:           alert.PackageName,
			PackageVersion:        alert.PackageVersion,
			SpdxLicenseExpression: alert.SPDXLicenseExpression,
		})
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckComplete", expectedProto)
}

func assertAlertStatusChangedEventPublished(t *testing.T, alert *models.Alert, previousStatus entities.AlertStatus,
	pullRequestID int64, tp *testpublisher.TestPublisher,
) {
	t.Helper()

	var enterpriseID *wrapperspb.Int64Value
	if alert.EnterpriseID != nil {
		enterpriseID = &wrapperspb.Int64Value{Value: int64(*alert.EnterpriseID)} // #nosec G115
	}
	expectedProto := &dependencygraphv1.LicenseComplianceAlertStatusChanged{
		Alert: &entities.LicenseComplianceAlert{
			AlertId:               int64(alert.ID),
			AlertNumber:           int32(alert.Number),
			Status:                entities.AlertStatus_ALERT_STATUS_CLOSED,
			CreatedAt:             timestamppb.New(alert.CreatedAt),
			RepositoryId:          int64(alert.RepositoryID),
			OrganizationId:        int64(alert.OrganizationID),
			EnterpriseId:          enterpriseID,
			PullRequestNumber:     int32(*alert.PullRequestNumber),
			PullRequestId:         pullRequestID,
			ManifestName:          alert.ManifestName,
			PackageManager:        entities.PackageManager(alert.PackageEcosystem),
			PackageName:           alert.PackageName,
			PackageVersion:        alert.PackageVersion,
			SpdxLicenseExpression: alert.SPDXLicenseExpression,
			ClosureReason:         entities.ClosureReason_CLOSURE_REASON_FIXED,
		},
		PreviousStatus: previousStatus,
		UserId:         0,
		Comment:        nil,
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedProto)
}

func TestStart_RestartFromPassedJob(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := uint64(100)
	baseSHA := "base-sha"
	commitSHA := "commit-sha"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)

	// Create an existing check job (starts in Starting status)
	enterpriseID := uint64(0)
	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      &enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     testhelpers.RandomIDForDatabase(),
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
	})
	require.NoError(t, err)

	// Update to Pass status to simulate a completed check
	checkJob.Status = models.Pass
	err = app.Subsystems.Storage.UpdateCheckJob(t.Context(), checkJob)
	require.NoError(t, err)

	// Build a request with same SHAs to trigger restart path
	checkRequest := &repocheck.Request{
		EnterpriseID:      enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     checkJob.PullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		Context:           "distributed",
		CommitSHA:         commitSHA,
		BaseSHA:           baseSHA,
	}

	// Restart the check job using Start
	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.Start(t.Context(), checkJob, checkRequest)
	require.NoError(t, err)

	// Verify the check job was restarted and completed
	updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.Equal(t, models.Pass, updatedJob.Status, "Check should pass after restart")
}

func TestStart_RestartFromFailStatus(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := uint64(100) // In seeds, this repo is not expecting any snapshots
	baseSHA := "base-sha"
	commitSHA := "commit-sha"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "BSD-3-Clause", "BSD-3-Clause", testhelpers.AllDistributionContexts, baseSHA, commitSHA, nil)

	// Create an existing check job (starts in Starting status)
	enterpriseID := uint64(0)
	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      &enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     testhelpers.RandomIDForDatabase(),
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           baseSHA,
		CommitSHA:         commitSHA,
	})
	require.NoError(t, err)

	// Update to Fail status to simulate a failed check
	checkJob.Status = models.Fail
	err = app.Subsystems.Storage.UpdateCheckJob(t.Context(), checkJob)
	require.NoError(t, err)

	// Build a request with same SHAs to trigger restart path
	checkRequest := &repocheck.Request{
		EnterpriseID:      enterpriseID,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     checkJob.PullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		Context:           "distributed",
		CommitSHA:         commitSHA,
		BaseSHA:           baseSHA,
	}

	// Restart the check job using Start
	checker := repocheck.NewChecker(app, app.StatsClient)
	err = checker.Start(t.Context(), checkJob, checkRequest)
	require.NoError(t, err)

	// Verify the check job was restarted and completed
	updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.Equal(t, models.Pass, updatedJob.Status, "Check should pass after restart with matching policy")
}

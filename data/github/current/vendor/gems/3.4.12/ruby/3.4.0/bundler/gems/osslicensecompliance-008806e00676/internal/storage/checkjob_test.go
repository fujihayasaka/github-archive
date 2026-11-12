package storage_test

import (
	"testing"
	"time"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/storage/sqlite"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetCheckJobWithNoMatchReturnsNil(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	result, err := s.GetCheckJob(ctx, 1, 1)
	r.NoError(err)
	r.Nil(result)
}

func TestNewCheckJobCreatesAJobThatIsRetrievable(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	enterpriseID := uint64(3)
	job := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 1,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &enterpriseID,
	}
	ctx := t.Context()
	returnedJob, err := s.CreateCheckJob(ctx, job)
	r.NoError(err)
	r.NotZero(returnedJob.ID)

	fetched, err := s.GetCheckJob(ctx, 10, 1)
	r.NoError(err)
	r.NotNil(fetched)
	r.Equal(returnedJob.ID, fetched.ID)

	validateValues := func(checkjob *models.CheckJob) {
		r.Equal(uint64(10), checkjob.RepositoryID)
		r.Equal(uint32(1), checkjob.PullRequestNumber)
		r.Equal(models.Starting, checkjob.Status)
		r.Equal("abc123", checkjob.BaseSHA)
		r.Equal("def456", checkjob.CommitSHA)
		r.Equal(uint64(2), checkjob.OrganizationID)
		r.Equal(uint64(3), *checkjob.EnterpriseID)
		r.NotZero(checkjob.CreatedAt)
		r.NotZero(checkjob.CheckStartedAt)
		now := time.Now()
		r.True(now.After(checkjob.CreatedAt))
		r.True(now.After(checkjob.CheckStartedAt))
	}
	validateValues(returnedJob)
	validateValues(fetched)
}

func TestUpdateCheckJobWillUpdateTheJobInTheDatabase(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	enterpriseID := uint64(3)
	sourcejob := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 1,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &enterpriseID,
	}
	checkjob, err := s.CreateCheckJob(ctx, sourcejob)
	r.NoError(err)
	r.NotNil(checkjob)

	checkjob.Status = models.Waiting
	checkjob.ExpectedSnapshots = 2
	checkjob.ReceivedSnapshots = 1
	checkjob.RepositoryID = 11 // This field should not change
	err = s.UpdateCheckJob(ctx, checkjob)
	r.NoError(err)

	nojob, err := s.GetCheckJob(ctx, 11, 1)
	r.NoError(err)
	r.Nil(nojob)

	updatedjob, err := s.GetCheckJob(ctx, 10, 1)
	r.NoError(err)
	r.NotNil(updatedjob)

	r.Equal(models.Waiting, updatedjob.Status)
	r.Equal(uint32(2), updatedjob.ExpectedSnapshots)
	r.Equal(uint32(1), updatedjob.ReceivedSnapshots)
	r.Equal(uint64(10), updatedjob.RepositoryID)
}

func TestCallingNewCheckJobTwiceReturnsAnError(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	enterpriseID := uint64(3)
	sourcejob := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 1,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &enterpriseID,
	}
	checkjob, err := s.CreateCheckJob(ctx, sourcejob)
	r.NoError(err)
	r.NotNil(checkjob)

	checkjob2, err := s.CreateCheckJob(ctx, sourcejob)
	r.Nil(checkjob2)
	r.ErrorIs(err, storage.ErrCheckAlreadyExists)
}

func TestGetCheckJobByCommitWithNoMatchReturnsNil(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	result, err := s.GetCheckJobByCommit(ctx, 1, "abc123")
	r.NoError(err)
	r.Nil(result)
}

func TestGetCheckJobByCommit(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	enterpriseID := uint64(3)
	job := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 1,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &enterpriseID,
	}
	ctx := t.Context()
	returnedJob, err := s.CreateCheckJob(ctx, job)
	r.NoError(err)
	fetched, err := s.GetCheckJobByCommit(ctx, 10, "def456")
	r.NoError(err)
	r.NotNil(fetched)
	r.Equal(returnedJob.ID, fetched.ID)
	r.Equal(uint32(1), fetched.PullRequestNumber)
}

func TestDeleteCheckJobsByDuration_DeleteWhenCreatedAtOlderThanDuration(t *testing.T) {
	db, err := sqlite.New(":memory:")
	require.NoError(t, err)

	t.Cleanup(func() {
		err = db.Close()
		if err != nil {
			t.Errorf("failed to close test db: %v", err)
		}
	})

	s, err := storage.NewStorage(db, nil, nil, nil, nil, nil, nil)

	enterpriseID := uint64(3)
	oldJob := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 1,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &enterpriseID,
	}

	ctx := t.Context()
	createdJob, err := s.CreateCheckJob(ctx, oldJob)
	require.NoError(t, err)

	// Manually set the old created at time to 1 hours ago
	jobStartedAt := time.Now().Add(-1 * time.Hour)
	query := `UPDATE olc_check_jobs SET check_started_at=? WHERE id=?`
	_, err = db.ExecContext(ctx, query, jobStartedAt, createdJob.ID)
	require.NoError(t, err)

	newJob := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 2,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &enterpriseID,
	}

	_, err = s.CreateCheckJob(ctx, newJob)
	require.NoError(t, err)

	deletedCount, err := s.DeleteCheckJobsStartedBefore(ctx, time.Hour)
	require.NoError(t, err)
	assert.Equal(t, int64(1), deletedCount, "should delete exactly 1 old job")

	getOldJob, err := s.GetCheckJob(ctx, oldJob.RepositoryID, oldJob.PullRequestNumber)
	require.NoError(t, err)
	assert.Nil(t, getOldJob, "job should be deleted")

	getNewJob, err := s.GetCheckJob(ctx, newJob.RepositoryID, newJob.PullRequestNumber)
	require.NoError(t, err)
	assert.Equal(t, newJob.RepositoryID, getNewJob.RepositoryID, "new job should not be deleted")
}

func TestDeleteCheckJobsByDuration_NoRowsToDelete(t *testing.T) {
	s := newSqliteStorage(t)

	deletedCount, err := s.DeleteCheckJobsStartedBefore(t.Context(), time.Hour)
	require.NoError(t, err)
	assert.Equal(t, int64(0), deletedCount, "should delete 0 rows when no old jobs exist")
}

func TestChangeCheckJobStatusFromAlertsWhenAlertsStillPresent(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	orgID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	newJob := models.CheckJob{
		RepositoryID:      repositoryID,
		PullRequestNumber: pullRequestNumber,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    orgID,
		EnterpriseID:      &enterpriseID,
	}

	dbJob, err := s.CreateCheckJob(ctx, newJob)
	r.NoError(err)

	dbJob.Status = models.Fail
	err = s.UpdateCheckJob(ctx, dbJob)
	r.NoError(err)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &enterpriseID,
		Status:                models.Open,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.1",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	_, err = s.CreateAlert(ctx, alert)
	r.NoError(err)

	err = s.ChangeCheckJobStatusFromAlerts(ctx, newJob.RepositoryID, newJob.PullRequestNumber)
	r.NoError(err)

	updatedJob, err := s.GetCheckJob(ctx, newJob.RepositoryID, newJob.PullRequestNumber)
	r.NoError(err)
	r.Equal(models.Fail, updatedJob.Status, "check job status should remain fail")
}

func TestChangeCheckJobStatusFromAlertsWhenAlertsClosed(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	orgID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	newJob := models.CheckJob{
		RepositoryID:      repositoryID,
		PullRequestNumber: pullRequestNumber,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    orgID,
		EnterpriseID:      &enterpriseID,
	}

	dbJob, err := s.CreateCheckJob(ctx, newJob)
	r.NoError(err)

	dbJob.Status = models.Fail
	err = s.UpdateCheckJob(ctx, dbJob)
	r.NoError(err)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &enterpriseID,
		Status:                models.Closed,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.1",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	_, err = s.CreateAlert(ctx, alert)
	r.NoError(err)

	err = s.ChangeCheckJobStatusFromAlerts(ctx, newJob.RepositoryID, newJob.PullRequestNumber)
	r.NoError(err)

	updatedJob, err := s.GetCheckJob(ctx, newJob.RepositoryID, newJob.PullRequestNumber)
	r.NoError(err)
	r.Equal(models.Pass, updatedJob.Status, "check job status should be updated to pass")
}

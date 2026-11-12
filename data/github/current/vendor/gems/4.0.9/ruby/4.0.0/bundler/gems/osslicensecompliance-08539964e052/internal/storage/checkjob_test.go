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
	forkRepositoryID := uint64(30)
	job := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 1,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &enterpriseID,
		ForkRepositoryID:  &forkRepositoryID,
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
		r.Equal(uint64(30), *checkjob.ForkRepositoryID)
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
	forkRepositoryID := uint64(30)
	sourcejob := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 1,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &enterpriseID,
		ForkRepositoryID:  &forkRepositoryID,
	}
	checkjob, err := s.CreateCheckJob(ctx, sourcejob)
	r.NoError(err)
	r.NotNil(checkjob)

	checkjob.Status = models.Waiting
	checkjob.ExpectedSnapshots = 2
	checkjob.ReceivedSnapshots = 1
	updatedForkRepositoryID := uint64(31)
	checkjob.ForkRepositoryID = &updatedForkRepositoryID
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
	r.Equal(uint64(31), *updatedjob.ForkRepositoryID)
	r.Equal(uint64(10), updatedjob.RepositoryID)
}

func TestCreateAndUpdateCheckJob_PersistsMissingDetectors(t *testing.T) {
	tests := []struct {
		name    string
		initial []string
		updated []string
	}{
		{
			name:    "nil on create defaults to empty list",
			initial: nil,
			updated: []string{"detector-one", "detector-two"},
		},
		{
			name:    "explicit empty slice on create stays empty",
			initial: []string{},
			updated: []string{"detector-one"},
		},
		{
			name:    "values on create are preserved through update",
			initial: []string{"detector-one", "detector-two"},
			updated: []string{},
		},
	}

	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := require.New(t)
			s := newSqliteStorage(t)
			ctx := t.Context()
			repoID := uint64(100 + i)
			pullRequestNumber := uint32(1)

			created, err := s.CreateCheckJob(ctx, models.CheckJob{
				RepositoryID:      repoID,
				PullRequestNumber: pullRequestNumber,
				BaseSHA:           "base",
				CommitSHA:         "head",
				OrganizationID:    2,
				MissingDetectors:  tt.initial,
			})
			r.NoError(err)
			r.NotNil(created)
			expectedAfterCreate := tt.initial
			if expectedAfterCreate == nil {
				expectedAfterCreate = []string{}
			}
			r.Equal(expectedAfterCreate, created.MissingDetectors, "persisted on create")

			created.MissingDetectors = tt.updated
			r.NoError(s.UpdateCheckJob(ctx, created))

			fetched, err := s.GetCheckJob(ctx, repoID, pullRequestNumber)
			r.NoError(err)
			expectedAfterUpdate := tt.updated
			if expectedAfterUpdate == nil {
				expectedAfterUpdate = []string{}
			}
			r.Equal(expectedAfterUpdate, fetched.MissingDetectors)
		})
	}
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

func TestGetCheckJobByCommitForForkRepository(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	enterpriseID := uint64(3)
	forkRepositoryID := uint64(30)
	job := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 1,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &enterpriseID,
		ForkRepositoryID:  &forkRepositoryID,
	}
	ctx := t.Context()
	returnedJob, err := s.CreateCheckJob(ctx, job)
	r.NoError(err)
	fetched, err := s.GetCheckJobByCommit(ctx, forkRepositoryID, "def456")
	r.NoError(err)
	r.NotNil(fetched)
	r.Equal(returnedJob.ID, fetched.ID)
	r.Equal(uint64(10), fetched.RepositoryID)
	r.Equal(forkRepositoryID, *fetched.ForkRepositoryID)
}

func TestCheckJobHeadRef(t *testing.T) {
	tests := []struct {
		name           string
		createHeadRef  *string
		updateHeadRef  *string // if non-nil, update to this value after create
		expectedCreate *string
		expectedUpdate *string // checked only when updateHeadRef is set
	}{
		{
			name:           "fully qualified ref round-trips",
			createHeadRef:  strPtr("refs/heads/feature"),
			expectedCreate: strPtr("refs/heads/feature"),
		},
		{
			name:           "bare branch name is normalized on create",
			createHeadRef:  strPtr("feature"),
			expectedCreate: strPtr("refs/heads/feature"),
		},
		{
			name:           "nil HeadRef round-trips as nil",
			createHeadRef:  nil,
			expectedCreate: nil,
		},
		{
			name:           "non-ASCII utf8 round-trips exactly",
			createHeadRef:  strPtr("feature/ünïcødé"),
			expectedCreate: strPtr("refs/heads/feature/ünïcødé"),
		},
		{
			name:           "update from nil to ref",
			createHeadRef:  nil,
			updateHeadRef:  strPtr("refs/heads/foo"),
			expectedCreate: nil,
			expectedUpdate: strPtr("refs/heads/foo"),
		},
		{
			name:           "update preserves existing ref when unchanged",
			createHeadRef:  strPtr("refs/heads/foo"),
			updateHeadRef:  strPtr("refs/heads/foo"),
			expectedCreate: strPtr("refs/heads/foo"),
			expectedUpdate: strPtr("refs/heads/foo"),
		},
	}

	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := require.New(t)
			s := newSqliteStorage(t)
			ctx := t.Context()
			repoID := uint64(200 + i)

			created, err := s.CreateCheckJob(ctx, models.CheckJob{
				RepositoryID:      repoID,
				PullRequestNumber: 1,
				BaseSHA:           "base",
				CommitSHA:         "head",
				OrganizationID:    2,
				HeadRef:           tt.createHeadRef,
			})
			r.NoError(err)
			r.NotNil(created)

			fetched, err := s.GetCheckJob(ctx, repoID, 1)
			r.NoError(err)
			r.NotNil(fetched)
			assert.Equal(t, tt.expectedCreate, fetched.HeadRef, "after create")

			if tt.updateHeadRef != nil {
				created.HeadRef = tt.updateHeadRef
				r.NoError(s.UpdateCheckJob(ctx, created))

				fetched2, err := s.GetCheckJob(ctx, repoID, 1)
				r.NoError(err)
				assert.Equal(t, tt.expectedUpdate, fetched2.HeadRef, "after update")
			}
		})
	}
}

func strPtr(s string) *string {
	return &s
}

func TestGetWaitingDependabotPendingCheckJobsByRef(t *testing.T) {
	const repoID = uint64(500)
	ref := "refs/heads/feature"

	// helper to create a check job with specific properties, then update it to the desired status/dependabot state
	createJob := func(t *testing.T, s *storage.Storage, job models.CheckJob) *models.CheckJob {
		t.Helper()
		r := require.New(t)
		ctx := t.Context()
		created, err := s.CreateCheckJob(ctx, job)
		r.NoError(err)
		r.NotNil(created)
		// Set desired status and dependabot_pending via update
		created.Status = job.Status
		created.DependabotPending = job.DependabotPending
		r.NoError(s.UpdateCheckJob(ctx, created))
		return created
	}

	t.Run("returns empty slice when no rows exist", func(t *testing.T) {
		r := require.New(t)
		s := newSqliteStorage(t)
		ctx := t.Context()
		results, err := s.GetWaitingDependabotPendingCheckJobsByRef(ctx, repoID, ref)
		r.NoError(err)
		r.Empty(results)
	})

	t.Run("returns matching waiting+dependabot_pending row", func(t *testing.T) {
		r := require.New(t)
		s := newSqliteStorage(t)
		ctx := t.Context()
		created := createJob(t, s, models.CheckJob{
			RepositoryID:      repoID,
			PullRequestNumber: 1,
			BaseSHA:           "base",
			CommitSHA:         "head",
			OrganizationID:    2,
			HeadRef:           strPtr(ref),
			Status:            models.Waiting,
			DependabotPending: true,
		})
		results, err := s.GetWaitingDependabotPendingCheckJobsByRef(ctx, repoID, ref)
		r.NoError(err)
		r.Len(results, 1)
		r.Equal(created.ID, results[0].ID)
	})

	t.Run("returns multiple matching rows", func(t *testing.T) {
		r := require.New(t)
		s := newSqliteStorage(t)
		ctx := t.Context()
		job1 := createJob(t, s, models.CheckJob{
			RepositoryID:      repoID,
			PullRequestNumber: 1,
			BaseSHA:           "base1",
			CommitSHA:         "head1",
			OrganizationID:    2,
			HeadRef:           strPtr(ref),
			Status:            models.Waiting,
			DependabotPending: true,
		})
		job2 := createJob(t, s, models.CheckJob{
			RepositoryID:      repoID,
			PullRequestNumber: 2,
			BaseSHA:           "base2",
			CommitSHA:         "head2",
			OrganizationID:    2,
			HeadRef:           strPtr(ref),
			Status:            models.Waiting,
			DependabotPending: true,
		})
		results, err := s.GetWaitingDependabotPendingCheckJobsByRef(ctx, repoID, ref)
		r.NoError(err)
		r.Len(results, 2)
		ids := []uint64{results[0].ID, results[1].ID}
		r.Contains(ids, job1.ID)
		r.Contains(ids, job2.ID)
	})

	t.Run("does NOT return row with dependabot_pending=false", func(t *testing.T) {
		r := require.New(t)
		s := newSqliteStorage(t)
		ctx := t.Context()
		createJob(t, s, models.CheckJob{
			RepositoryID:      repoID,
			PullRequestNumber: 1,
			BaseSHA:           "base",
			CommitSHA:         "head",
			OrganizationID:    2,
			HeadRef:           strPtr(ref),
			Status:            models.Waiting,
			DependabotPending: false,
		})
		results, err := s.GetWaitingDependabotPendingCheckJobsByRef(ctx, repoID, ref)
		r.NoError(err)
		r.Empty(results)
	})

	t.Run("does NOT return row with status != Waiting", func(t *testing.T) {
		r := require.New(t)
		s := newSqliteStorage(t)
		ctx := t.Context()
		createJob(t, s, models.CheckJob{
			RepositoryID:      repoID,
			PullRequestNumber: 1,
			BaseSHA:           "base",
			CommitSHA:         "head",
			OrganizationID:    2,
			HeadRef:           strPtr(ref),
			Status:            models.Pass,
			DependabotPending: true,
		})
		results, err := s.GetWaitingDependabotPendingCheckJobsByRef(ctx, repoID, ref)
		r.NoError(err)
		r.Empty(results)
	})

	t.Run("does NOT return row in different repository", func(t *testing.T) {
		r := require.New(t)
		s := newSqliteStorage(t)
		ctx := t.Context()
		createJob(t, s, models.CheckJob{
			RepositoryID:      repoID + 1, // different repo
			PullRequestNumber: 1,
			BaseSHA:           "base",
			CommitSHA:         "head",
			OrganizationID:    2,
			HeadRef:           strPtr(ref),
			Status:            models.Waiting,
			DependabotPending: true,
		})
		results, err := s.GetWaitingDependabotPendingCheckJobsByRef(ctx, repoID, ref)
		r.NoError(err)
		r.Empty(results)
	})

	t.Run("does NOT return row with NULL head_ref", func(t *testing.T) {
		r := require.New(t)
		s := newSqliteStorage(t)
		ctx := t.Context()
		createJob(t, s, models.CheckJob{
			RepositoryID:      repoID,
			PullRequestNumber: 1,
			BaseSHA:           "base",
			CommitSHA:         "head",
			OrganizationID:    2,
			HeadRef:           nil, // NULL
			Status:            models.Waiting,
			DependabotPending: true,
		})
		results, err := s.GetWaitingDependabotPendingCheckJobsByRef(ctx, repoID, ref)
		r.NoError(err)
		r.Empty(results)
	})

	t.Run("returns row matching via fork_repository_id", func(t *testing.T) {
		r := require.New(t)
		s := newSqliteStorage(t)
		ctx := t.Context()
		forkRepoID := uint64(999)
		created := createJob(t, s, models.CheckJob{
			RepositoryID:      repoID,      // base repo
			ForkRepositoryID:  &forkRepoID, // fork/head repo
			PullRequestNumber: 1,
			BaseSHA:           "base",
			CommitSHA:         "head",
			OrganizationID:    2,
			HeadRef:           strPtr(ref),
			Status:            models.Waiting,
			DependabotPending: true,
		})
		// Look up by fork repo ID (the event's repository_id for fork PRs)
		results, err := s.GetWaitingDependabotPendingCheckJobsByRef(ctx, forkRepoID, ref)
		r.NoError(err)
		r.Len(results, 1)
		r.Equal(created.ID, results[0].ID)
	})

	t.Run("empty headRef returns empty slice without error", func(t *testing.T) {
		r := require.New(t)
		s := newSqliteStorage(t)
		ctx := t.Context()
		createJob(t, s, models.CheckJob{
			RepositoryID:      repoID,
			PullRequestNumber: 1,
			BaseSHA:           "base",
			CommitSHA:         "head",
			OrganizationID:    2,
			HeadRef:           strPtr(ref),
			Status:            models.Waiting,
			DependabotPending: true,
		})
		results, err := s.GetWaitingDependabotPendingCheckJobsByRef(ctx, repoID, "")
		r.NoError(err)
		r.Empty(results)
	})
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
		Status:                models.AlertStatusOpen,
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
		Status:                models.AlertStatusClosed,
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

func TestPassCheckJobIfNoAlertsStep_UpdatedWhenAllAlertsClosed(t *testing.T) {
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

	// Create a closed alert — no open alerts remain
	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &enterpriseID,
		Status:                models.AlertStatusClosed,
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

	step, result := storage.NewPassCheckJobIfNoAlertsStep(repositoryID, pullRequestNumber)
	tx := s.NewTransactor(ctx)
	tx.AddStep(step)
	err = tx.Execute()
	r.NoError(err)

	r.True(result.Updated, "result.Updated should be true when check job was updated to pass")

	updatedJob, err := s.GetCheckJob(ctx, repositoryID, pullRequestNumber)
	r.NoError(err)
	r.Equal(models.Pass, updatedJob.Status)
}

func TestPassCheckJobIfNoAlertsStep_NotUpdatedWhenOpenAlertsRemain(t *testing.T) {
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

	// Create an open alert
	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &enterpriseID,
		Status:                models.AlertStatusOpen,
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

	step, result := storage.NewPassCheckJobIfNoAlertsStep(repositoryID, pullRequestNumber)
	tx := s.NewTransactor(ctx)
	tx.AddStep(step)
	err = tx.Execute()
	r.NoError(err)

	r.False(result.Updated, "result.Updated should be false when open alerts remain")

	updatedJob, err := s.GetCheckJob(ctx, repositoryID, pullRequestNumber)
	r.NoError(err)
	r.Equal(models.Fail, updatedJob.Status, "check job should remain fail")
}

func TestPassCheckJobIfNoAlertsStep_NotUpdatedWhenAlreadyPass(t *testing.T) {
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

	dbJob.Status = models.Pass
	err = s.UpdateCheckJob(ctx, dbJob)
	r.NoError(err)

	step, result := storage.NewPassCheckJobIfNoAlertsStep(repositoryID, pullRequestNumber)
	tx := s.NewTransactor(ctx)
	tx.AddStep(step)
	err = tx.Execute()
	r.NoError(err)

	r.False(result.Updated, "result.Updated should be false when check job was already pass")
}

package storage

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/github/osslicensecompliance/internal/models"
)

const ocjSelect = `SELECT id, status, created_at, check_started_at, organization_id, enterprise_id,
		pull_request_id, base_sha, commit_sha, expected_snapshots, received_snapshots,
		repository_id, pull_request_number
		FROM olc_check_jobs`

// GetCheckJob returns the check job for a given repository and pull request number
// (number being the number visible in the UI for the PR, not the large, globally unique
// ID for the PR). If there is no matching check job, it returns nil.
func (s *Storage) GetCheckJob(ctx context.Context, repositoryID uint64, pullRequestNumber uint32) (*models.CheckJob, error) {
	query := ocjSelect + `
		WHERE repository_id=? AND pull_request_number=?`
	row := s.db.QueryRowContext(ctx, query, repositoryID, pullRequestNumber)

	return createCheckJobFromRow(row)
}

func createCheckJobFromRow(row *sql.Row) (*models.CheckJob, error) {
	checkjob := &models.CheckJob{}
	var status string
	err := row.Scan(&checkjob.ID, &status, &checkjob.CreatedAt, &checkjob.CheckStartedAt,
		&checkjob.OrganizationID, &checkjob.EnterpriseID, &checkjob.PullRequestID,
		&checkjob.BaseSHA, &checkjob.CommitSHA, &checkjob.ExpectedSnapshots, &checkjob.ReceivedSnapshots,
		&checkjob.RepositoryID, &checkjob.PullRequestNumber)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}

	checkjob.Status = models.NewCheckStatus(status)
	return checkjob, nil
}

// GetCheckJobByCommit returns the check job for a given repository and commit SHA.
// commitSHA might _seem_ globally unique, but there can be a repository that's
// a fork of another and therefore has the same commits. It's unlikely that there
// will be two pull requests with the same commit SHA (especially in the same repository),
// so we're just going to work with the first one we find.
// If there is no matching check job, it returns nil.
func (s *Storage) GetCheckJobByCommit(ctx context.Context, repositoryID uint64, commitSHA string) (*models.CheckJob, error) {
	query := ocjSelect + `
		WHERE commit_sha=? AND repository_id=?`
	row := s.db.QueryRowContext(ctx, query, commitSHA, repositoryID)
	return createCheckJobFromRow(row)
}

// ErrCheckAlreadyExists is returned when an attempt is made to create a new check for a repo+PR that already exists in the DB.
var ErrCheckAlreadyExists = errors.New("check already exists")

// CreateCheckJob creates a new check job in the database based on the model passed in.
// The returned CheckJob will have its ID field populated.
func (s *Storage) CreateCheckJob(ctx context.Context, jobInfo models.CheckJob) (*models.CheckJob, error) {
	status := models.Starting.String()
	if jobInfo.Status == models.Waiting {
		status = models.Waiting.String()
	}
	createdAt := time.Now()
	checkStartedAt := createdAt
	// Insert the check job into the database, setting the created at time
	query := `INSERT INTO olc_check_jobs (status, created_at, check_started_at, repository_id, organization_id, enterprise_id,
		pull_request_id, pull_request_number, base_sha, commit_sha, expected_snapshots, received_snapshots) 
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
	_, err := s.db.ExecContext(ctx, query, status, createdAt, checkStartedAt, jobInfo.RepositoryID,
		jobInfo.OrganizationID, jobInfo.EnterpriseID, jobInfo.PullRequestID, jobInfo.PullRequestNumber,
		jobInfo.BaseSHA, jobInfo.CommitSHA, jobInfo.ExpectedSnapshots, jobInfo.ReceivedSnapshots)
	if err != nil {
		errString := err.Error()
		errString = strings.ToLower(errString)
		if strings.Contains(errString, "duplicate") || strings.Contains(errString, "unique") {
			return nil, ErrCheckAlreadyExists
		}
		return nil, err
	}
	return s.GetCheckJob(ctx, jobInfo.RepositoryID, jobInfo.PullRequestNumber)
}

// UpdateCheckJob is used to update the job in the database. The row should already be there.
// Fields which will be updated: status, base_sha, commit_sha, expected_snapshots, received_snapshots
func (s *Storage) UpdateCheckJob(ctx context.Context, checkjob *models.CheckJob) error {
	status := checkjob.Status.String()

	query := `UPDATE olc_check_jobs SET status=?, base_sha=?, commit_sha=?, expected_snapshots=?, received_snapshots=? WHERE
		id=?`
	_, err := s.db.ExecContext(ctx, query, status, checkjob.BaseSHA, checkjob.CommitSHA, checkjob.ExpectedSnapshots, checkjob.ReceivedSnapshots, checkjob.ID)
	return err
}

// DeleteCheckJobsStartedBefore deletes all check jobs where check_started_at is older than the specified duration
func (s *Storage) DeleteCheckJobsStartedBefore(ctx context.Context, duration time.Duration) (int64, error) {
	cutoffTime := time.Now().Add(-duration)
	query := `DELETE FROM olc_check_jobs WHERE check_started_at < ?`
	result, err := s.db.ExecContext(ctx, query, cutoffTime)
	if err != nil {
		return 0, err
	}
	rowsAffected, err := result.RowsAffected()
	return rowsAffected, err
}

// ChangeCheckJobStatusFromAlerts updates the status of a check job to passed if all of the alerts
// for the pull request have been closed.
func (s *Storage) ChangeCheckJobStatusFromAlerts(ctx context.Context, repositoryID uint64, pullRequestNumber uint32) error {
	alerts, err := s.GetOpenAlerts(ctx, repositoryID, &pullRequestNumber)
	if err != nil {
		return err
	}
	if len(alerts) == 0 {
		checkJob, err := s.GetCheckJob(ctx, repositoryID, pullRequestNumber)
		if err != nil || checkJob == nil {
			return err
		}
		checkJob.Status = models.Pass
		err = s.UpdateCheckJob(ctx, checkJob)
		if err != nil {
			return err
		}
	}
	return nil
}

package storage

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/github/osslicensecompliance/internal/models"
)

const ocjSelect = `SELECT id, status, created_at, check_started_at, organization_id, enterprise_id,
		pull_request_id, base_sha, commit_sha, expected_snapshots, received_snapshots,
		repository_id, pull_request_number, fork_repository_id, head_ref, missing_detectors, dependabot_pending
		FROM olc_check_jobs`

// GetCheckJob returns the check job for a given repository and pull request number
// (number being the number visible in the UI for the PR, not the large, globally unique
// ID for the PR). If there is no matching check job, it returns nil.
func (s *Storage) GetCheckJob(ctx context.Context, repositoryID uint64, pullRequestNumber uint32) (*models.CheckJob, error) {
	query := ocjSelect + `
		WHERE repository_id=? AND pull_request_number=?`
	row := s.db.QueryRowContext(ctx, query, repositoryID, pullRequestNumber)

	cj, err := createCheckJobFromRow(row)
	if err != nil {
		return nil, fmt.Errorf("get check job: %w", err)
	}
	return cj, nil
}

func createCheckJobFromRow(row *sql.Row) (*models.CheckJob, error) {
	checkjob := &models.CheckJob{}
	var status string
	var missingDetectorsJSON []byte
	var dependabotPending int
	err := row.Scan(&checkjob.ID, &status, &checkjob.CreatedAt, &checkjob.CheckStartedAt,
		&checkjob.OrganizationID, &checkjob.EnterpriseID, &checkjob.PullRequestID,
		&checkjob.BaseSHA, &checkjob.CommitSHA, &checkjob.ExpectedSnapshots, &checkjob.ReceivedSnapshots,
		&checkjob.RepositoryID, &checkjob.PullRequestNumber, &checkjob.ForkRepositoryID, &checkjob.HeadRef, &missingDetectorsJSON, &dependabotPending)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}

	checkjob.Status = models.NewCheckStatus(status)
	checkjob.DependabotPending = dependabotPending != 0
	checkjob.MissingDetectors, err = decodeMissingDetectors(missingDetectorsJSON)
	if err != nil {
		return nil, fmt.Errorf("failed to decode missing_detectors: %w", err)
	}
	return checkjob, nil
}

// decodeMissingDetectors parses the JSON-encoded list stored in the
// missing_detectors column. An empty/nil column is treated as an empty list.
func decodeMissingDetectors(raw []byte) ([]string, error) {
	if len(raw) == 0 {
		return []string{}, nil
	}
	var detectors []string
	if err := json.Unmarshal(raw, &detectors); err != nil {
		return nil, err
	}
	if detectors == nil {
		return []string{}, nil
	}
	return detectors, nil
}

// encodeMissingDetectors returns the JSON encoding to persist for the column.
// A nil slice is serialised as "[]" so we never write SQL NULL.
func encodeMissingDetectors(detectors []string) ([]byte, error) {
	if detectors == nil {
		detectors = []string{}
	}
	return json.Marshal(detectors)
}

// GetCheckJobByCommit returns the check job for a given repository and commit SHA.
// commitSHA might _seem_ globally unique, but there can be a repository that's
// a fork of another and therefore has the same commits. It's unlikely that there
// will be two pull requests with the same commit SHA (especially in the same repository),
// so we're just going to work with the first one we find.
// If there is no matching check job, it returns nil.
func (s *Storage) GetCheckJobByCommit(ctx context.Context, repositoryID uint64, commitSHA string) (*models.CheckJob, error) {
	// Match either a same-repo PR (common case) or a fork PR where
	// fork_repository_id equals the snapshot event's repository ID.
	query := ocjSelect + `
		WHERE commit_sha=? AND ((repository_id=? AND fork_repository_id IS NULL) OR fork_repository_id=?)`
	row := s.db.QueryRowContext(ctx, query, commitSHA, repositoryID, repositoryID)
	cj, err := createCheckJobFromRow(row)
	if err != nil {
		return nil, fmt.Errorf("get check job by commit: %w", err)
	}
	return cj, nil
}

// ErrCheckAlreadyExists is returned when an attempt is made to create a new check for a repo+PR that already exists in the DB.
var ErrCheckAlreadyExists = errors.New("check already exists")

// GetWaitingDependabotPendingCheckJobsByRef returns all CheckJobs in Waiting status
// with dependabot_pending = true whose head_ref matches the given ref for the given
// repository. The repository predicate mirrors GetCheckJobByCommit: it matches
// same-repo PRs (repository_id = ?) and fork PRs (fork_repository_id = ?).
// Returns an empty slice (not nil, not error) when nothing matches.
// An empty headRef returns an empty slice immediately.
func (s *Storage) GetWaitingDependabotPendingCheckJobsByRef(ctx context.Context, repositoryID uint64, headRef string) ([]*models.CheckJob, error) {
	if headRef == "" {
		return []*models.CheckJob{}, nil
	}
	query := ocjSelect + `
		WHERE head_ref=? AND dependabot_pending=1 AND status=?
		AND ((repository_id=? AND fork_repository_id IS NULL) OR fork_repository_id=?)`
	rows, err := s.db.QueryContext(ctx, query, headRef, models.Waiting.String(), repositoryID, repositoryID)
	if err != nil {
		return nil, fmt.Errorf("GetWaitingDependabotPendingCheckJobsByRef: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var results []*models.CheckJob
	for rows.Next() {
		checkjob := &models.CheckJob{}
		var status string
		var missingDetectorsJSON []byte
		var dependabotPending int
		err := rows.Scan(&checkjob.ID, &status, &checkjob.CreatedAt, &checkjob.CheckStartedAt,
			&checkjob.OrganizationID, &checkjob.EnterpriseID, &checkjob.PullRequestID,
			&checkjob.BaseSHA, &checkjob.CommitSHA, &checkjob.ExpectedSnapshots, &checkjob.ReceivedSnapshots,
			&checkjob.RepositoryID, &checkjob.PullRequestNumber, &checkjob.ForkRepositoryID, &checkjob.HeadRef, &missingDetectorsJSON, &dependabotPending)
		if err != nil {
			return nil, fmt.Errorf("GetWaitingDependabotPendingCheckJobsByRef scan: %w", err)
		}
		checkjob.Status = models.NewCheckStatus(status)
		checkjob.DependabotPending = dependabotPending != 0
		checkjob.MissingDetectors, err = decodeMissingDetectors(missingDetectorsJSON)
		if err != nil {
			return nil, fmt.Errorf("GetWaitingDependabotPendingCheckJobsByRef decode missing_detectors: %w", err)
		}
		results = append(results, checkjob)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("GetWaitingDependabotPendingCheckJobsByRef rows: %w", err)
	}
	if results == nil {
		results = []*models.CheckJob{}
	}
	return results, nil
}

// CreateCheckJob creates a new check job in the database based on the model passed in.
// The returned CheckJob will have its ID field populated.
func (s *Storage) CreateCheckJob(ctx context.Context, jobInfo models.CheckJob) (*models.CheckJob, error) {
	status := models.Starting.String()
	if jobInfo.Status == models.Waiting {
		status = models.Waiting.String()
	}
	createdAt := time.Now()
	checkStartedAt := createdAt
	missingDetectors, err := encodeMissingDetectors(jobInfo.MissingDetectors)
	if err != nil {
		return nil, fmt.Errorf("failed to encode missing_detectors: %w", err)
	}
	// Insert the check job into the database, setting the created at time
	normalizedHeadRef := normalizeHeadRefToNullable(jobInfo.HeadRef)
	query := `INSERT INTO olc_check_jobs (status, created_at, check_started_at, repository_id, organization_id, enterprise_id,
		fork_repository_id, head_ref, pull_request_id, pull_request_number, base_sha, commit_sha, expected_snapshots, received_snapshots, missing_detectors, dependabot_pending)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
	_, err = s.db.ExecContext(ctx, query, status, createdAt, checkStartedAt, jobInfo.RepositoryID,
		jobInfo.OrganizationID, jobInfo.EnterpriseID, jobInfo.ForkRepositoryID, normalizedHeadRef, jobInfo.PullRequestID, jobInfo.PullRequestNumber,
		jobInfo.BaseSHA, jobInfo.CommitSHA, jobInfo.ExpectedSnapshots, jobInfo.ReceivedSnapshots, missingDetectors, jobInfo.DependabotPending)
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
// Fields which will be updated: status, base_sha, commit_sha, expected_snapshots, received_snapshots, fork_repository_id, missing_detectors, dependabot_pending
func (s *Storage) UpdateCheckJob(ctx context.Context, checkjob *models.CheckJob) error {
	status := checkjob.Status.String()
	missingDetectors, err := encodeMissingDetectors(checkjob.MissingDetectors)
	if err != nil {
		return fmt.Errorf("failed to encode missing_detectors: %w", err)
	}

	normalizedHeadRef := normalizeHeadRefToNullable(checkjob.HeadRef)
	query := `UPDATE olc_check_jobs SET status=?, base_sha=?, commit_sha=?, expected_snapshots=?, received_snapshots=?, fork_repository_id=?, head_ref=?, missing_detectors=?, dependabot_pending=? WHERE
		id=?`
	_, err = s.db.ExecContext(ctx, query, status, checkjob.BaseSHA, checkjob.CommitSHA, checkjob.ExpectedSnapshots, checkjob.ReceivedSnapshots, checkjob.ForkRepositoryID, normalizedHeadRef, missingDetectors, checkjob.DependabotPending, checkjob.ID)
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

// PassCheckJobResult tracks whether the passCheckJobIfNoAlertsStep actually updated
// a check job to pass. It is populated after the step executes.
type PassCheckJobResult struct {
	Updated bool
}

type passCheckJobIfNoAlertsStep struct {
	repositoryID      uint64
	pullRequestNumber uint32
	result            *PassCheckJobResult
}

func (pcj *passCheckJobIfNoAlertsStep) Execute(ctx context.Context, tx *sql.Tx) error {
	// Run a query to update checkjob status to pass if there are no open alerts for the PR
	query := `
		UPDATE olc_check_jobs
		SET status = ?
		WHERE repository_id = ? AND pull_request_number = ? AND status != ? AND NOT EXISTS (
			SELECT 1 FROM olc_alerts
			WHERE olc_alerts.repository_id = olc_check_jobs.repository_id
			AND olc_alerts.pull_request_number = olc_check_jobs.pull_request_number
			AND olc_alerts.status != ?
		)`
	result, err := tx.ExecContext(ctx, query, models.Pass.String(), pcj.repositoryID, pcj.pullRequestNumber, models.Pass.String(), models.AlertStatusClosed.String())
	if err != nil {
		return fmt.Errorf("failed to update check job status: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected for check job update: %w", err)
	}
	pcj.result.Updated = rowsAffected > 0

	return nil
}

// NewPassCheckJobIfNoAlertsStep creates a step that will update the status of a check job to passed if all of the alerts
// for the pull request have been closed. This is used as part of the remediation process to automatically pass check jobs
// when alerts are closed due to policy updates or becoming outdated.
// The returned PassCheckJobResult indicates whether the check job was actually updated to pass.
// Callers can inspect the result after the transactor executes to determine if a progress event should be published.
func NewPassCheckJobIfNoAlertsStep(repositoryID uint64, pullRequestNumber uint32) (Step, *PassCheckJobResult) {
	result := &PassCheckJobResult{}
	return &passCheckJobIfNoAlertsStep{
		repositoryID:      repositoryID,
		pullRequestNumber: pullRequestNumber,
		result:            result,
	}, result
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

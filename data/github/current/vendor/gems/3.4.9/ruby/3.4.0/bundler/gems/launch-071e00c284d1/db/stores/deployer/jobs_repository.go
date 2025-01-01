package deployer

import (
	"context"
	"database/sql"
	"strings"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

// JobsRepository holds methods for loading/saving from the workflow_jobs DB table.
type JobsRepository interface {
	GetWorkflowJobFromJobID(ctx context.Context, workflowID, jobID string) (*WorkflowJob, error)
	GetWorkflowJobsFromJobIds(ctx context.Context, externalIDs []string) (map[string]string, error)
	CreateWorkflowJob(ctx context.Context, dbID int64, workflowID, externalJobID string, checkRunID types.GlobalID, executionDbID *int64) (int64, error)
	UpdateBillingChecked(ctx context.Context, workflowID, jobID string, billingChecked bool) error
	TouchWorkflowJob(ctx context.Context, ID int64) error
}

type azpJobsRepository struct {
	db          *asql.SQL
	obs         *observability.Observability
	gidMigrator GlobalIDMigrator
}

type WorkflowJob struct {
	ID                       int64
	WorkflowBuildID          int64
	ExternalJobID            string
	CheckRunID               types.GlobalID
	WorkflowBuildExecutionID *int64
	BillingChecked           bool
}

func NewJobsRepository(db *asql.SQL, obs *observability.Observability, gidMigrator GlobalIDMigrator) *azpJobsRepository {
	return &azpJobsRepository{
		db:          db,
		obs:         obs,
		gidMigrator: gidMigrator,
	}
}

// GetWorkflowJobIdFromJobID will return a WorkflowJob representing the record with the given JobID.
//
// Not yet implemented: Could accept a workflowID (uuid) as an argument and confirm that the returned entry matches, similar to metadata.go.
func (r *azpJobsRepository) GetWorkflowJobFromJobID(ctx context.Context, workflowID, jobID string) (*WorkflowJob, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `SELECT id, workflow_build_id, external_job_id, check_run_id, workflow_build_execution_id, billing_checked
		FROM workflow_jobs
		WHERE external_job_id = ?`

	rows, err := r.db.QueryContextWith(ctx, query,
		asql.WithName("GetWorkflowJobFromJobID"),
		buildGUID(workflowID, jobID),
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	defer rows.Close()

	workflowJobs := []*WorkflowJob{}
	for rows.Next() {
		workflowJob := &WorkflowJob{}
		err := rows.Scan(&workflowJob.ID, &workflowJob.WorkflowBuildID, &workflowJob.ExternalJobID, &workflowJob.CheckRunID, &workflowJob.WorkflowBuildExecutionID, &workflowJob.BillingChecked)
		if err != nil {
			return nil, tracing.RecordError(span, err)
		}

		workflowJobs = append(workflowJobs, workflowJob)
	}

	if rows.Err() != nil {
		return nil, tracing.RecordError(span, rows.Err())
	}

	return selectLatestWorkflowJob(workflowJobs)
}

func (r *azpJobsRepository) GetWorkflowJobsFromJobIds(ctx context.Context, externalJobIDs []string) (map[string]string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	mapCheckRunIds := make(map[string]string)

	if len(externalJobIDs) < 1 {
		return mapCheckRunIds, nil
	}

	query := `SELECT id, workflow_build_id, external_job_id, check_run_id, workflow_build_execution_id
		FROM workflow_jobs
		WHERE external_job_id in (?` + strings.Repeat(",?", len(externalJobIDs)-1) + `)
		ORDER BY created_at DESC`

	anyStrings := make([]any, len(externalJobIDs))

	for i, v := range externalJobIDs {
		anyStrings[i] = v
	}

	rows, err := r.db.QueryContextWith(ctx, query,
		asql.WithName("GetWorkflowJobsFromJobIds"),
		anyStrings...)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	defer rows.Close()

	workflowJobs := []*WorkflowJob{}
	for rows.Next() {
		workflowJob := &WorkflowJob{}
		err := rows.Scan(&workflowJob.ID, &workflowJob.WorkflowBuildID, &workflowJob.ExternalJobID, &workflowJob.CheckRunID, &workflowJob.WorkflowBuildExecutionID)
		if err != nil {
			return nil, tracing.RecordError(span, err)
		}

		workflowJobs = append(workflowJobs, workflowJob)
	}

	if rows.Err() != nil {
		return nil, tracing.RecordError(span, rows.Err())
	}

	for _, wj := range workflowJobs {
		if _, present := mapCheckRunIds[wj.ExternalJobID]; !present {
			mapCheckRunIds[wj.ExternalJobID] = wj.CheckRunID.String()
		}
	}

	return mapCheckRunIds, nil
}

// CreateWorkflowJob creates a WorkflowJob row in the DB.
func (r *azpJobsRepository) CreateWorkflowJob(ctx context.Context, dbID int64, workflowID, externalJobID string, checkRunID types.GlobalID, executionDbID *int64) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	checkRunNextID, err := r.gidMigrator.GetNextGlobalID(ctx, checkRunID.String())
	if err != nil {
		return 0, tracing.RecordError(span, errors.Wrap(err, "Failed to get next check suite id for azpJobsRepository"))
	}

	// Log if legacy global ID is being updated
	if checkRunNextID != checkRunID {
		r.obs.Counter(ctx, "global_ids.replace_wfj_legacy_id", statter.Tags{"operation": "CreateWorkflowJob", "column": "check_run_id"}, 1)
		r.obs.Logger.Debug(ctx, "Replacing legacy global id with next value for workflow_jobs column",
			kvp.String("gh.launch.column", "check_run_id"),
			kvp.String("gh.launch.legacy_global_id", checkRunID.String()),
			kvp.String("gh.launch.next_global_id", checkRunNextID.String()))
	}

	now := time.Now().UTC()
	const query = `INSERT INTO workflow_jobs
		(workflow_build_id, external_job_id, check_run_id, check_run_next_id, created_at, updated_at, workflow_build_execution_id)
		VALUES (?, ?, ?, ?, ?, ?, ?)`
	operation := "CreateWorkflowJobWithExecution"
	res, err := mysqldb.WithDeadlockRetry(ctx, operation, r.obs.Statter, func() (sql.Result, error) {
		return r.db.ExecContextWith(ctx, query,
			asql.WithName(operation),
			dbID,
			buildGUID(workflowID, externalJobID),
			wrapNullString(checkRunNextID.String()),
			wrapNullString(checkRunNextID.String()),
			now,
			now,
			executionDbID,
		)
	})
	if err != nil {
		return 0, tracing.RecordError(span, err)
	}
	id, err := res.LastInsertId()
	if err != nil {
		return 0, tracing.RecordError(span, err)
	}
	return id, nil
}

// TODO: Remove this
// JobID isn't globally unique, it's only unique per run
// This method temporarily combines the two IDs to produce an actual GUID
func buildGUID(workflowID, jobID string) string {
	return workflowID + "," + jobID
}

// UpdateBillingChecked will update the billing_checked column of a WorkflowJob DB record.
func (r *azpJobsRepository) UpdateBillingChecked(ctx context.Context, workflowID, jobID string, billingChecked bool) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `UPDATE workflow_jobs SET billing_checked = ? WHERE external_job_id = ?`
	_, err := r.db.ExecContextWith(ctx,
		query,
		asql.WithName("UpdateBillingChecked"),
		billingChecked,
		buildGUID(workflowID, jobID))
	if err != nil {
		return tracing.RecordError(span, err)
	}
	return nil
}

// TouchWorkflowJob will update the updated_at column of a WorkflowJob DB record.
func (r *azpJobsRepository) TouchWorkflowJob(ctx context.Context, ID int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `UPDATE workflow_jobs SET updated_at = ? WHERE id = ?`

	operation := "TouchWorkflowJob"
	_, err := mysqldb.WithDeadlockRetry(ctx, operation, r.obs.Statter, func() (sql.Result, error) {
		return r.db.ExecContextWith(ctx,
			query,
			asql.WithName(operation),
			time.Now().UTC(),
			ID)
	})
	if err != nil {
		return tracing.RecordError(span, err)
	}
	return nil
}

// There's a possible race condition where more than one check run is created for a given external_job_id, this function
// handles this condition. Note that because the check runs are created concurrently, it's not sufficient to
// select the latest entry in `workflow_jobs`. See https://github.com/github/c2c-actions-experience/issues/3256
func selectLatestWorkflowJob(workflowJobs []*WorkflowJob) (*WorkflowJob, error) {
	if len(workflowJobs) == 0 {
		return nil, nil
	}

	if len(workflowJobs) == 1 {
		return workflowJobs[0], nil
	}

	var newCheckRunDatabaseID int64 = -1
	var nwj *WorkflowJob

	for _, cwj := range workflowJobs {
		_, currCheckRunDatabaseID, err := cwj.CheckRunID.Decode()
		if err != nil {
			return nil, err
		}

		if currCheckRunDatabaseID > newCheckRunDatabaseID {
			nwj = cwj
			newCheckRunDatabaseID = currCheckRunDatabaseID
		}
	}

	return nwj, nil
}

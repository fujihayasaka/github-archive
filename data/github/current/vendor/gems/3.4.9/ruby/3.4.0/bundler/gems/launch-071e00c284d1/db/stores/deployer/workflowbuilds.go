package deployer

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/facebookgo/clock"
	"github.com/github/go-kvp"
	"github.com/google/uuid"
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/payloads"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/requiredworkflowutils"
	"github.com/github/launch/workflowbuild/build"
)

const (
	// we only started persisting events as of #1476
	unknownEvent = "unknown"

	checkSuiteIDColumnName     = "check_suite_id"
	executingActorIDColumnName = "executing_actor_id"
	repositoryIDColumnName     = "repository_id"
)

type WorkflowBuildsRepositoryReadOnly interface {
	// GetDataForTokenRequest gets data needed to fulfill a token request.
	GetDataForTokenRequest(ctx context.Context, planID string) (*DataForTokenRequest, bool, error)

	// GetWorkflowsToHeal returns workflows that need to be healed
	GetWorkflowsToHeal(ctx context.Context, from, to time.Duration) ([]DataForHealer, bool, error)
}

// WorkflowBuildsRepository saves build.WorkflowBuilds.
type WorkflowBuildsRepository interface {
	WorkflowBuildsRepositoryReadOnly // Include all ReadOnly methods

	// Persist stores a WorkflowBuild status to the database.
	// Should be called before Runner.Run() starts the build, to prevent races between persistence and the first message received from execution.
	// Returns the persisted workflow build database ID and if the payload was
	// successfully persisted.
	Persist(
		ctx context.Context,
		build *build.WorkflowBuild,
		repositoryID types.GlobalID,
		eventSHA types.CommitSha,
		eventRef types.GitRef,
		flowIdentifier string,
		workflowMetadata *metadata.WorkflowMetadata,
		perms *tokens.PermissionSettings,
		eventPayload []byte,
		executingActorID types.GlobalID,
		triggeringActorID types.GlobalID,
		githubTenant ghtenant.GitHubTenant,
	) (int64, types.WorkflowExecutionID, time.Time, bool, error)

	// Complete simply marks the build as completed.
	Complete(ctx context.Context, completedAt time.Time, azpCompletedAt time.Time, workflowDatabaseID int64, conclusion build.WorkflowState) error

	// PersistError inserts an error row for a check suite for errors occur before we have things like workflow identifiers or workflowMetadata
	// TODO it'd be good to de-duplicate this on ref too - at the moment we'll only see the
	// latest syntax error across all branches for a given workflow file name
	PersistError(
		ctx context.Context,
		repoID types.GlobalID,
		uuid types.WorkflowExecutionID,
		eventName string,
		eventSHA types.CommitSha,
		eventRef types.GitRef,
		requestID string,
		checkSuiteID types.GlobalID,
		filePath string,
		executingActorID, triggeringActorID types.GlobalID,
	) (int64, error)

	// TransitionToError records a failure for a given workflow build row, setting completed_at and state
	TransitionToError(
		ctx context.Context,
		workflowBuildID int64,
		checkSuiteID types.GlobalID,
	) error

	ResetWorkflowBuildState(
		ctx context.Context,
		checkSuiteID types.GlobalID,
		b *build.WorkflowBuild,
		perms *tokens.PermissionSettings,
		md *metadata.WorkflowMetadata,
		actorID types.GlobalID,
		allowFourNinesReset bool,
	) (*WorkflowBuildResetContext, error)

	// SetWasDelayed sets that some jobs in the run were delayed
	SetWasDelayed(ctx context.Context, workflowDatabaseID int64) error

	// SetCheckSuiteInformation stores the check suite for this build
	SetCheckSuiteInformation(ctx context.Context, workflowBuildID int64, checkSuiteID types.GlobalID, workflowRunID int64, workflowRunNumber int64) error

	// GetStateByCheckSuiteID loads a CheckSuiteState by CheckSuiteID
	GetStateByCheckSuiteID(ctx context.Context, checkSuiteID types.GlobalID) (*types.CheckSuiteState, bool, error)

	// GetWorkflowBuildStateByCheckSuiteID loads a WorkflowBuildState by CheckSuiteID
	GetWorkflowBuildStateByCheckSuiteID(ctx context.Context, checkSuiteID types.GlobalID) (*WorkflowBuildState, bool, error)

	// GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs loads WorkflowBuildStates by Actor ID for pending (i.e., not completed workflow builds) queued
	// within the last 30 days and excluded from given repoIDs
	GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(ctx context.Context, actorID types.GlobalID, excludeRepoIds []types.GlobalID, limit int64, previousMaxID int64) ([]*WorkflowBuildState, error)

	// GetDataForPrejobtoken loads event data by UUID
	GetDataForPrejobtoken(ctx context.Context, UUID string) (*DataForPrejobtoken, bool, error)

	// GetDataForStatusPostback loads check suite and reporting info by UUID
	GetDataForStatusPostback(ctx context.Context, UUID string) (*DataForStatusPostback, bool, error)

	// GetWaitingOnResourceCheckRunID loads check run info based on external Job ID
	GetWaitingOnResourceCheckRunID(ctx context.Context, externalJobID string) (*DataForWaitingOnCheckRunResource, bool, error)

	// GetWaitingOnResourceCheckSuiteID loads check suite info based on external plan ID
	GetWaitingOnResourceCheckSuiteID(ctx context.Context, UUID string) (*DataForWaitingOnCheckSuiteResource, bool, error)

	// TransitionTo transitions a build to a state, returning true if it caused a state transition
	TransitionTo(ctx context.Context, workflowBuildID int64, state build.WorkflowState) (bool, error)

	// TransitionToQueued transitions a build into the queue state and sets the external build ID
	TransitionToQueued(ctx context.Context, workflowBuildID int64, externalBuildID string) error

	// GetWorkflowState returns the state of a persisted workflow identified by delivery id, name, and path, if it exists.
	GetWorkflowState(ctx context.Context, webhookDeliveryID, eventName string, workflowFileReference types.WorkflowFileReference) (*build.WorkflowState, bool, error)

	// GetWorkflowRerunState returns the state of a persisted workflow_execution identified by delivery id, if it exists.
	GetWorkflowRerunState(ctx context.Context, webhookDeliveryID, eventName, rerunWebhookDeliveryID string, workflowFileReference types.WorkflowFileReference) (*build.WorkflowState, bool, error)

	// GetDataForGatePostback loads check suite and reporting info by UUID
	GetDataForGatePostback(ctx context.Context, externalJobID string) (*DataForGatePostback, bool, error)

	// GetDataForSecurityDetails loads event data including the payload by UUID
	GetDataForSecurityDetails(ctx context.Context, UUID string) (*DataForSecurityDetails, bool, error)

	// GetWorkflowBuildPayload Retrieves just the payload for a given workflow build
	GetWorkflowBuildPayload(ctx context.Context, workflowBuildID int64, repoID types.GlobalID) ([]byte, error)
}

var _ WorkflowBuildsRepository = (*workflowBuildsRepository)(nil)

type workflowBuildsRepository struct {
	db            *asql.SQL
	payloads      payloads.Store
	executions    WorkflowBuildExecutionsRepository
	logger        logger.Logger
	stats         statter.Statter
	clock         clock.Clock
	gidMigrator   GlobalIDMigrator
	isMultiTenant bool
}

type WorkflowBuildResetContext struct {
	WorkflowExecutionID *types.WorkflowExecutionID
	Attempt             int64
	Backend             types.WorkflowBackend
}

// NewWorkflowBuildsRepository instantiates a new instance of the WorkflowBuildsRepository
func NewWorkflowBuildsRepository(
	db *asql.SQL,
	logger logger.Logger,
	stats statter.Statter,
	clock clock.Clock,
	payloads payloads.Store,
	executions WorkflowBuildExecutionsRepository,
	gidMigrator GlobalIDMigrator,
	isMultiTenant bool,
) *workflowBuildsRepository {
	return &workflowBuildsRepository{
		db:            db,
		payloads:      payloads,
		executions:    executions,
		logger:        logger,
		stats:         stats,
		clock:         clock,
		gidMigrator:   gidMigrator,
		isMultiTenant: isMultiTenant,
	}
}

// NewWorkflowBuildsRepositoryReadOnly instantiates a new instance of the NewWorkflowBuildsRepositoryReadOnly
func NewWorkflowBuildsRepositoryReadOnly(db *asql.SQL, logger logger.Logger, stats statter.Statter, clock clock.Clock, gidMigrator GlobalIDMigrator, isMultiTenant bool) WorkflowBuildsRepositoryReadOnly {
	return &workflowBuildsRepository{
		db:            db,
		logger:        logger,
		stats:         stats,
		clock:         clock,
		gidMigrator:   gidMigrator,
		isMultiTenant: isMultiTenant,
	}
}

func (w *workflowBuildsRepository) TransitionTo(ctx context.Context, workflowBuildID int64, state build.WorkflowState) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	now := w.clock.Now().UTC()

	buildQuery := `UPDATE workflow_builds
	SET state = ?
	WHERE state < ?
		AND id = ?
	`

	rc, err := w.db.ExecContextWith(ctx, buildQuery, asql.WithName("TransitionTo"), state, state, workflowBuildID)
	if err != nil {
		return false, tracing.RecordError(span, err)
	}

	c, err := rc.RowsAffected()
	if err != nil {
		return false, tracing.RecordError(span, err)
	}

	err = w.executions.TransitionTo(ctx, workflowBuildID, state, now)
	if err != nil {
		return false, tracing.RecordError(span, err)
	}

	return c > 0, nil
}

func (w *workflowBuildsRepository) SetCheckSuiteInformation(ctx context.Context, workflowBuildID int64, checkSuiteID types.GlobalID, workflowRunID int64, workflowRunNumber int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	checkSuiteNextID, err := w.gidMigrator.GetNextGlobalID(ctx, checkSuiteID.String())
	if err != nil {
		return tracing.RecordError(span, errors.Wrap(err, "Failed to get next check suite id for workflowBuildsRepository"))
	}

	if checkSuiteNextID != checkSuiteID {
		w.logGlobalIDReplacement(ctx, "SetCheckSuiteInformation", "check_suite_id", checkSuiteID, checkSuiteNextID)
	}

	const query = `UPDATE workflow_builds SET
			check_suite_id = ?,
			check_suite_next_id = ?,
			workflow_run_id=?,
			workflow_run_number=?
		WHERE id = ?
		`
	_, err = w.db.ExecContextWith(ctx,
		query,
		asql.WithName("SetCheckSuiteInformation"),
		wrapNullString(checkSuiteNextID.String()),
		wrapNullString(checkSuiteNextID.String()),
		workflowRunID,
		workflowRunNumber,
		workflowBuildID,
	)
	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (w *workflowBuildsRepository) Persist(
	ctx context.Context,
	b *build.WorkflowBuild,
	repositoryID types.GlobalID,
	eventSHA types.CommitSha,
	eventRef types.GitRef,
	flowIdentifier string,
	workflowMetadata *metadata.WorkflowMetadata,
	perms *tokens.PermissionSettings,
	eventPayload []byte,
	executingActorID,
	triggeringActorID types.GlobalID,
	githubTenant ghtenant.GitHubTenant,
) (int64, types.WorkflowExecutionID, time.Time, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var eventTime time.Time
	var githubTenantID int64
	if w.isMultiTenant {
		err := githubTenant.Validate(w.isMultiTenant)
		if err != nil {
			return -1, types.NilWorkflowExecutionID, eventTime, false, tracing.RecordError(span, errors.Wrap(err, "Failed to validate github tenant for workflowBuildsRepository"))
		}

		githubTenantID = githubTenant.ID
	}

	repositoryNextID, err := w.gidMigrator.GetNextGlobalID(ctx, repositoryID.String())
	if err != nil {
		return -1, types.NilWorkflowExecutionID, eventTime, false, tracing.RecordError(span, errors.Wrap(err, "Failed to get next repository id for workflowBuildsRepository"))
	}

	executingActorNextID, err := w.gidMigrator.GetNextGlobalID(ctx, executingActorID.String())
	if err != nil {
		return -1, types.NilWorkflowExecutionID, eventTime, false, tracing.RecordError(span, errors.Wrap(err, "Failed to get next executing actor id for workflowBuildsRepository"))
	}

	imposerRepositoryID, processedWorkflowFilePath, err := preProcessWorkflowFilePath(b.WorkflowFilePath)
	if err != nil {
		return -1, types.NilWorkflowExecutionID, eventTime, false, tracing.RecordError(span, errors.Wrap(err, "Failed to fetch required workflow's source repoID for workflowBuildsRepository"))
	}

	// Insert workflow_builds row:
	now := w.clock.Now().UTC()
	requestID := mw.GetGitHubRequestID(ctx)

	// Logging both event time and origin time so we can evaluate which one to use as event_time. Ideally for our Run Start Delay SLO we want one that represents
	// when the user performed an action (pushed, opened a pull request), not when the webhook was created or received.
	w.logger.Debug(ctx, "Persisting workflow build",
		kvp.String("gh.launch.workflow_build.execution_id", b.ExecutionID.String()),
		kvp.Time("gh.launch.workflow_build.event_time", b.EventTime),
		kvp.Time("gh.launch.workflow_build.origin_time", b.OriginTime),
	)

	eventTime = b.OriginTime
	if b.OriginTime.IsZero() {
		eventTime = now
	}

	if repositoryNextID != repositoryID {
		w.logGlobalIDReplacement(ctx, "Persist", "repository_id", repositoryID, repositoryNextID)
	}
	if executingActorNextID != executingActorID {
		w.logGlobalIDReplacement(ctx, "Persist", "executing_actor_id", executingActorID, executingActorNextID)
	}

	if len(b.Event) > 40 {
		w.logger.Error(ctx, "event string greater than 40 characters",
			kvp.String("gh.launch.workflow.execution.uuid", b.ExecutionID.String()),
			kvp.String("gh.launch.event.name", b.Event),
			kvp.Int("gh.launch.event.length", len(b.Event)),
			kvp.String("gh.launch.workflow.identifier", flowIdentifier),
		)
		return -1, types.NilWorkflowExecutionID, eventTime, false, errors.New("event string greater than 40 characters")
	}

	query := `INSERT INTO workflow_builds SET
		uuid=?,
		event_time=?,
		created_at=?,
		repository_id=?,
		repository_next_id=?,
		commit_sha=?,
		event_ref=?,
		workflow_id=?,
		request_id=?,
		webhook_delivery_id=?,
		workflow_file_path=?,
		event=?,
		checkout_sha=?,
		checkout_ref=?,
		reporting_metadata=CONVERT(? USING utf8),
		token_permissions=CONVERT(? USING utf8),
		executing_actor_id=?,
		executing_actor_next_id=?,
		imposer_repository_id=?,
		github_tenant_id=?,
		backend=?,
		pinned_workflow_ref=?,
		workflow_sha=?
	ON DUPLICATE KEY UPDATE id=id`

	if w.isMultiTenant {
		// Proxima is setup for strict mode, and the parser allows up to 512 characters here.
		flowIdentifier = trimVarCharColumnData(flowIdentifier, 255)
	}

	params := []any{
		b.ExecutionID,
		eventTime,
		now,
		repositoryNextID,
		repositoryNextID,
		eventSHA,
		eventRef,
		flowIdentifier,
		requestID,
		b.WebhookDeliveryID,
		processedWorkflowFilePath,
		b.Event,
		b.CheckoutSHA,
		b.CheckoutRef,
		workflowMetadata,
		perms,
		wrapNullString(executingActorNextID.String()),
		wrapNullString(executingActorNextID.String()),
		imposerRepositoryID,
		wrapNullInt64(githubTenantID),
		b.Backend,
		b.FileReference.Ref,
		b.FileReference.SHA,
	}

	res, err := w.db.ExecContextWith(ctx,
		query,
		asql.WithName("PersistWorkflowBuild"),
		params...)

	if err != nil {
		return -1, types.NilWorkflowExecutionID, eventTime, false, tracing.RecordError(span, err)
	}

	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return -1, types.NilWorkflowExecutionID, eventTime, false, tracing.RecordError(span, err)
	}

	persisted := true
	executionID := b.ExecutionID
	var workflowDatabaseID int64

	switch rowsAffected {
	case 1:
		{
			workflowDatabaseID, err = res.LastInsertId()
			if err != nil {
				return -1, types.NilWorkflowExecutionID, eventTime, false, tracing.RecordError(span, err)
			}

			// Only persist the payload when a new workflow_build row was inserted
			persisted = w.persistEventPayload(ctx, workflowDatabaseID, eventPayload, repositoryID)

			_, err := w.executions.Persist(ctx, b, workflowDatabaseID, triggeringActorID, 1, workflowMetadata)
			if err != nil {
				return -1, types.NilWorkflowExecutionID, eventTime, false, tracing.RecordError(span, err)
			}
		}

	case 0:
		{
			// An existing row was set to its current values, get the ID and execution ID.
			// A previous iteration used LAST_INSERT_ID(id) but vitess doesn't support that.

			if err := w.db.QueryScanWith(
				ctx,
				"SELECT id, uuid FROM workflow_builds WHERE webhook_delivery_id = ? AND workflow_file_path = ? AND event = ? AND imposer_repository_id = ? AND pinned_workflow_ref = ? AND workflow_sha = ?",
				asql.WithName("PersistWorkflowBuild.GetUUID"),
				asql.Params(b.WebhookDeliveryID, processedWorkflowFilePath, b.Event, imposerRepositoryID, b.FileReference.Ref, b.FileReference.SHA),
				&workflowDatabaseID,
				&executionID,
			); err != nil {
				return -1, types.NilWorkflowExecutionID, eventTime, false, tracing.RecordError(span, errors.Wrap(err, "Could not read uuid when persisting build"))
			}
		}
	}

	return workflowDatabaseID, executionID, eventTime, persisted, nil
}

// persistEventPayload attempts to persist the event payload in the database
// with a reference to the workflow_build_id. It returns whether or not the payload was
// properly persisted.
func (w *workflowBuildsRepository) persistEventPayload(ctx context.Context, workflowBuildID int64, eventPayload []byte, repoID types.GlobalID) bool {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	_, err := w.payloads.Persist(ctx, workflowBuildID, eventPayload, repoID)
	if err != nil {
		w.logger.Report(ctx, errors.Wrap(err, "error persisting event payload"), kvp.Int64("gh.launch.workflow_build.id", workflowBuildID))
		span.RecordError(err)
		return false
	}

	return true
}

// ResetWorkflowBuildState resets a workflow build for reruns
// Returns an error if the build is not complete.
// When creating a new build, we need to reset the `completed_at` value, while
// also updating the uuid and external_build_id to the new workflow build's values.
// When allowFourNinesReset param is true, we perform different validations to reset the build.
func (w *workflowBuildsRepository) ResetWorkflowBuildState(
	ctx context.Context,
	checkSuiteID types.GlobalID,
	b *build.WorkflowBuild,
	perms *tokens.PermissionSettings,
	md *metadata.WorkflowMetadata,
	actorID types.GlobalID,
	allowFourNinesReset bool,
) (*WorkflowBuildResetContext, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	actorNextID, err := w.gidMigrator.GetNextGlobalID(ctx, actorID.String())
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "Failed to get next executing actor id for workflowBuildsRepository"))
	}

	checkSuiteNextID, checkSuiteNextIDColumn, err := w.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, checkSuiteID.String(), checkSuiteIDColumnName)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "Failed to get next check suite id and column for workflowBuildsRepository"))
	}

	// Check FF to see if we should use the next ID
	if actorNextID != actorID {
		w.logGlobalIDReplacement(ctx, "ResetWorkflowBuildState", "executing_actor_id", actorID, actorNextID)
	}

	queryName := "ResetWorkflowBuildState"
	query := fmt.Sprintf(`UPDATE workflow_builds SET
		completed_at = NULL,
		queued_at = NULL,
		state = ?,
		uuid = ?,
		rerun = true,
		token_permissions=CONVERT(? USING utf8),
		reporting_metadata=CONVERT(? USING utf8),
		executing_actor_id = ?,
		executing_actor_next_id = ?,
		backend = ?
		WHERE %s = ? AND state > ?`, checkSuiteNextIDColumn)

	if allowFourNinesReset {
		queryName += "_FourNines"
		query += " AND queued_at IS NOT NULL"
	} else {
		query += " AND completed_at IS NOT NULL"
	}

	query += ` LIMIT 1`

	params := []any{
		build.WorkflowStateNone,
		b.ExecutionID,
		perms,
		md,
		wrapNullString(actorNextID.String()),
		wrapNullString(actorNextID.String()),
		b.Backend,
		checkSuiteNextID,
		build.WorkflowStateNone,
	}

	res, err := w.db.ExecContextWith(
		ctx,
		query,
		asql.WithName(queryName),
		params...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	numRowsReset, err := res.RowsAffected()
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "Could not get rows affected"))
	}

	var executionID types.WorkflowExecutionID
	var workflowDatabaseID, lastAttemptNumber int64
	var backend types.WorkflowBackend
	if err := w.db.QueryScanWith(
		ctx,
		fmt.Sprintf(`SELECT workflow_builds.id,
				workflow_builds.uuid,
				COALESCE(MAX(attempt), 0) attempt,
				workflow_builds.backend
		FROM workflow_builds
		LEFT JOIN workflow_build_executions
			ON workflow_build_executions.workflow_build_id = workflow_builds.id
		WHERE workflow_builds.%s = ?
			AND workflow_builds.completed_at IS NULL
			AND workflow_builds.rerun = true
		GROUP BY workflow_builds.id`, checkSuiteNextIDColumn),
		asql.WithName("ResetWorkflowBuildState.GetExecutionID"),
		asql.Params(checkSuiteNextID),
		&workflowDatabaseID,
		&executionID,
		&lastAttemptNumber,
		&backend,
	); err != nil {
		if err == sql.ErrNoRows {
			return nil, tracing.RecordError(span, errors.Wrap(err, "Could not find workflow build to reset"))
		}

		return nil, tracing.RecordError(span, errors.Wrap(err, "Could not read ExecutionID from reset workflow build"))
	}

	// If we didn't reset a workflow_build row we likely have a build that failed
	// to even get queued on a rerun. Lets use the actual executionID that we just
	// SELECTed for our update to the workflow_build_executions table.
	// https://github.com/github/c2c-actions-experience/issues/6499
	if numRowsReset == 0 {
		b.ExecutionID = executionID
	}

	newAttemptNumber := lastAttemptNumber + 1

	_, err = w.executions.Persist(ctx, b, workflowDatabaseID, actorID, newAttemptNumber, md)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "Could not persist new workflow execution"))
	}

	return &WorkflowBuildResetContext{
		WorkflowExecutionID: &executionID,
		Attempt:             newAttemptNumber,
		Backend:             backend,
	}, nil
}

func (w *workflowBuildsRepository) Complete(ctx context.Context, completedAt time.Time, azpCompletedAt time.Time, workflowDatabaseID int64, conclusion build.WorkflowState) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `UPDATE workflow_builds SET completed_at = ?, state = ? WHERE id = ? AND completed_at IS NULL AND state < ?`
	_, err := w.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("Complete"),
		completedAt,
		conclusion,
		workflowDatabaseID,
		conclusion,
	)
	if err != nil {
		return tracing.RecordError(span, err)
	}

	err = w.executions.Complete(ctx, workflowDatabaseID, completedAt, azpCompletedAt, conclusion)
	return tracing.RecordError(span, err)
}

func (w *workflowBuildsRepository) TransitionToQueued(ctx context.Context, workflowDatabaseID int64, externalBuildID string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	now := w.clock.Now().UTC()

	const query = `UPDATE workflow_builds SET state = ?, queued_at = ? WHERE id = ? and state < ?`
	_, err := w.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("TransitionToQueued_WithoutExternalBuildID"),
		build.WorkflowStateQueued,
		now,
		workflowDatabaseID,
		build.WorkflowStateQueued)
	if err != nil {
		return tracing.RecordError(span, err)
	}

	err = w.executions.TransitionToQueued(ctx, workflowDatabaseID, externalBuildID, now)
	return tracing.RecordError(span, err)
}

func (w *workflowBuildsRepository) GetWorkflowState(ctx context.Context, webhookDeliveryID, eventName string, workflowFileReference types.WorkflowFileReference) (*build.WorkflowState, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	imposerRepositoryID, processedWorkflowFilePath, err := preProcessWorkflowFilePath(workflowFileReference.Path)
	if err != nil {
		return nil, false, tracing.RecordError(span, errors.Wrap(err, "Failed to fetch required workflow's source repoID for GetWorkflowState"))
	}

	var workflowState *build.WorkflowState

	if err := w.db.QueryScanWith(
		ctx,
		`SELECT state FROM workflow_builds WHERE webhook_delivery_id = ? AND event = ? AND workflow_file_path = ? AND imposer_repository_id = ? AND pinned_workflow_ref = ? AND workflow_sha = ?`,
		asql.WithName("GetWorkflowState"),
		asql.Params(webhookDeliveryID, eventName, processedWorkflowFilePath, imposerRepositoryID, workflowFileReference.Ref, workflowFileReference.SHA),
		&workflowState,
	); err != nil {
		if err == sql.ErrNoRows {
			return nil, false, nil
		}

		return nil, false, err
	}

	return workflowState, true, nil
}

func (w *workflowBuildsRepository) GetWorkflowRerunState(ctx context.Context, webhookDeliveryID, eventName, rerunWebhookDeliveryID string, workflowFileReference types.WorkflowFileReference) (*build.WorkflowState, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	imposerRepositoryID, processedWorkflowFilePath, err := preProcessWorkflowFilePath(workflowFileReference.Path)
	if err != nil {
		return nil, false, tracing.RecordError(span, errors.Wrap(err, "Failed to fetch required workflow's source repoID for GetWorkflowRerunState"))
	}

	var workflowState *build.WorkflowState
	if err := w.db.QueryScanWith(
		ctx,
		`SELECT executions.state
		FROM workflow_builds builds
		LEFT JOIN workflow_build_executions executions
			ON builds.uuid = executions.plan_id
		WHERE builds.webhook_delivery_id = ?
		AND builds.event = ?
		AND builds.workflow_file_path = ?
		AND executions.webhook_delivery_id = ?
		AND builds.imposer_repository_id = ?
		AND builds.pinned_workflow_ref = ?
		AND builds.workflow_sha = ?`,
		asql.WithName("GetWorkflowRerunState"),
		asql.Params(webhookDeliveryID, eventName, processedWorkflowFilePath, rerunWebhookDeliveryID, imposerRepositoryID, workflowFileReference.Ref, workflowFileReference.SHA),
		&workflowState,
	); err != nil {
		if err == sql.ErrNoRows {
			return nil, false, nil
		}

		return nil, false, err
	}

	return workflowState, true, nil
}

func (w *workflowBuildsRepository) SetWasDelayed(ctx context.Context, workflowDatabaseID int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	err := w.executions.SetWasDelayed(ctx, workflowDatabaseID)
	return tracing.RecordError(span, err)
}

func (w *workflowBuildsRepository) GetStateByCheckSuiteID(
	ctx context.Context,
	checkSuiteGlobalID types.GlobalID,
) (*types.CheckSuiteState, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	checkSuiteNextID, checkSuiteNextIDColumn, err := w.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, checkSuiteGlobalID.String(), checkSuiteIDColumnName)
	if err != nil {
		return nil, false, tracing.RecordError(span, errors.Wrap(err, "Failed to get next check suite id and column for workflowBuildsRepository"))
	}

	query := fmt.Sprintf(`SELECT
			b.id,
			b.repository_id,
			x.webhook_delivery_id,
			b.commit_sha,
			b.event_ref,
			b.checkout_sha,
			b.checkout_ref,
			b.executing_actor_id,
			b.workflow_id,
			b.workflow_file_path,
			b.event,
			b.workflow_run_id,
			b.workflow_run_number,
			b.check_suite_id,
			b.imposer_repository_id,
			x.plan_id,
			b.backend
		FROM workflow_builds AS b
		JOIN workflow_build_executions AS x
			ON b.id = x.workflow_build_id
		WHERE b.%s = ?
		ORDER BY x.id DESC
		LIMIT 1`, checkSuiteNextIDColumn)

	rows, err := w.db.QueryContextWith(ctx, query, asql.WithName("getStateByCheckSuiteID"), checkSuiteNextID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	defer rows.Close()
	if !rows.Next() {
		return nil, false, nil
	}

	var workflowBuildDatabaseID int64
	var repositoryID types.GlobalID
	var webhookDeliveryIDDB sql.NullString
	var eventSHA types.CommitSha
	var eventRef types.GitRef
	var checkoutSHA types.CommitSha
	var checkoutRef types.GitRef
	var executingActorID types.GlobalID
	var flowIdentifier string
	var workflowFilePath string
	var event string
	var workflowRunID, workflowRunNumber, imposerRepositoryID int64
	var executionID types.WorkflowExecutionID
	var backend types.WorkflowBackend
	// During the transition phase of global id migration, this may not match what is supplied in as checkSuiteGlobalID
	var checkSuiteRetrievedID types.GlobalID
	if err := rows.Scan(&workflowBuildDatabaseID, &repositoryID, &webhookDeliveryIDDB, &eventSHA, &eventRef, &checkoutSHA, &checkoutRef, &executingActorID, &flowIdentifier, &workflowFilePath, &event, &workflowRunID, &workflowRunNumber, &checkSuiteRetrievedID, &imposerRepositoryID, &executionID, &backend); err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	if rows.Err() != nil {
		return nil, false, tracing.RecordError(span, rows.Err())
	}

	var eventPayload []byte
	eventPayload, err = w.payloads.Get(ctx, workflowBuildDatabaseID, repositoryID)
	if err != nil {
		return nil, false, tracing.RecordError(span, errors.Wrap(err, "error fetching workflow build payload"))
	}

	var webhookDeliveryID *string
	if webhookDeliveryIDDB.Valid {
		webhookDeliveryID = &webhookDeliveryIDDB.String
	}

	if imposerRepositoryID > 0 {
		workflowFilePath = postProcessWorkflowFilePath(workflowFilePath, imposerRepositoryID)
	}

	return &types.CheckSuiteState{
		WorkflowBuildDatabaseID: workflowBuildDatabaseID,
		RepositoryID:            repositoryID,
		WebhookDeliveryID:       webhookDeliveryID,
		EventSHA:                eventSHA,
		EventRef:                eventRef,
		CheckoutSHA:             checkoutSHA,
		CheckoutRef:             checkoutRef,
		ExecutedAsActorID:       executingActorID,
		FlowIdentifier:          flowIdentifier,
		CheckSuiteIDPair: types.IDPair{
			GlobalID: checkSuiteRetrievedID,
		},
		WorkflowFilePath:  workflowFilePath,
		Event:             event,
		EventPayload:      eventPayload,
		WorkflowRunID:     workflowRunID,
		WorkflowRunNumber: workflowRunNumber,
		ExecutionID:       executionID,
		Backend:           backend,
	}, true, nil
}

type WorkflowBuildState struct {
	DatabaseID        int64
	ExecutionID       types.WorkflowExecutionID
	QueuedAt          *time.Time
	StartedAt         *time.Time
	CompletedAt       *time.Time
	Identifier        string
	ExternalBuildID   string
	RepositoryID      types.GlobalID
	CommitSha         types.CommitSha
	CheckSuiteID      types.GlobalID
	State             build.WorkflowState
	WebhookDeliveryID *string
	Event             string
	TokenPermissions  *tokens.PermissionSettings
	WorkflowRunID     int64
	WorkflowRunNumber int64
	WorkflowFilePath  string
	WasDelayed        bool
	ActorID           types.GlobalID
	WorkflowMetadata  *metadata.WorkflowMetadata
	GitHubTenantID    *int64
	Backend           types.WorkflowBackend
}

func (w *workflowBuildsRepository) GetWorkflowBuildStateByCheckSuiteID(ctx context.Context, checkSuiteID types.GlobalID) (*WorkflowBuildState, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	checkSuiteNextID, checkSuiteNextIDColumn, err := w.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, checkSuiteID.String(), checkSuiteIDColumnName)
	if err != nil {
		return nil, false, tracing.RecordError(span, errors.Wrap(err, "Failed to get next check suite id and column for workflowBuildsRepository"))
	}

	query := fmt.Sprintf(`SELECT %s
		FROM workflow_builds AS b
		JOIN workflow_build_executions AS x
			ON b.id = x.workflow_build_id
		WHERE b.%s = ?
		ORDER BY x.id DESC
		LIMIT 1`, workflowBuildAndExecutionFields, checkSuiteNextIDColumn)
	rows, err := w.db.QueryContextWith(ctx, query, asql.WithName("GetWorkflowBuildStateByCheckSuiteID"), checkSuiteNextID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	defer rows.Close()

	if !rows.Next() {
		return nil, false, nil
	}

	wb, err := w.getWorkflowBuildStateFromRow(ctx, rows)
	if err != nil {
		return nil, false, err
	}

	if rows.Err() != nil {
		return nil, false, tracing.RecordError(span, rows.Err())
	}

	return wb, true, nil
}

func (w *workflowBuildsRepository) GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(ctx context.Context, actorID types.GlobalID, excludeRepoIDs []types.GlobalID, limit int64, previousMaxID int64) ([]*WorkflowBuildState, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const checkBuildsWithinHours = 720

	excludedReposFragment := ""
	var excludeRepoNextIDsInterfaces []any
	if len(excludeRepoIDs) > 0 {
		excludeRepoIDStrs := make([]string, len(excludeRepoIDs))
		for i, id := range excludeRepoIDs {
			excludeRepoIDStrs[i] = id.String()
		}

		excludeRepoNextIDs, repositoryNextIDColumn, err := w.gidMigrator.GetNextGlobalIDsAndColumnForQuery(ctx, excludeRepoIDStrs, repositoryIDColumnName)
		if err != nil {
			return nil, tracing.RecordError(span, errors.Wrap(err, "Failed to get next repository ids and column for workflowBuildsRepository"))
		}

		excludeRepoNextIDsInterfaces = globalIDsToEmptyInterfaces(excludeRepoNextIDs)
		excludedReposFragment = fmt.Sprintf("AND b.%s NOT IN (%s)", repositoryNextIDColumn, mysqldb.Placeholders(len(excludeRepoNextIDs)))
	}

	executingActorNextID, executingActorNextIDColumn, err := w.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, actorID.String(), executingActorIDColumnName)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "Failed to get next executing actor id and column for workflowBuildsRepository"))
	}

	query := fmt.Sprintf(`
		SELECT %s
		FROM workflow_builds AS b
		JOIN workflow_build_executions AS x
			ON b.id = x.workflow_build_id
		WHERE b.%s = ?
			AND (x.state = ? OR x.state = ?)
			AND x.queued_at >= ? - INTERVAL ? HOUR
			AND b.id > ?
			%s
		ORDER BY b.id ASC
		LIMIT ?`, workflowBuildAndExecutionFields, executingActorNextIDColumn, excludedReposFragment)

	args := []any{
		executingActorNextID,
		build.WorkflowStateQueued,
		build.WorkflowStateStarted,
		w.clock.Now().UTC(),
		checkBuildsWithinHours,
		previousMaxID,
	}
	args = append(args, excludeRepoNextIDsInterfaces...)
	args = append(args, limit)

	rows, err := w.db.QueryContextWith(
		ctx,
		query,
		asql.WithName("GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs"),
		args...)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "error in executing the query"))
	}
	defer rows.Close()
	var wfStates []*WorkflowBuildState
	for rows.Next() {
		wfState, err := w.getWorkflowBuildStateFromRow(ctx, rows)
		if err != nil {
			return nil, tracing.RecordError(span, errors.Wrap(err, "error extracting the results from row"))
		}
		wfStates = append(wfStates, wfState)
	}

	err = rows.Err()
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "error unwrapping results from db"))
	}

	return wfStates, nil
}

func globalIDsToEmptyInterfaces(globalIDs []types.GlobalID) []any {
	emptyInterfaces := make([]any, 0, len(globalIDs))
	for _, gid := range globalIDs {
		emptyInterfaces = append(emptyInterfaces, gid)
	}
	return emptyInterfaces
}

var workflowBuildAndExecutionFields = strings.Join([]string{
	"b.id",
	"x.plan_id",
	"b.check_suite_id",
	"x.queued_at",
	"x.started_at",
	"b.workflow_id",
	"x.completed_at",
	"x.external_build_id",
	"b.repository_id",
	"b.commit_sha",
	"b.event",
	"x.webhook_delivery_id",
	"x.state",
	"b.workflow_run_id",
	"b.workflow_run_number",
	"b.workflow_file_path",
	"x.was_delayed",
	"b.executing_actor_id",
	"b.reporting_metadata",
	"b.imposer_repository_id",
	"b.backend",
}, ",")

func (w *workflowBuildsRepository) getWorkflowBuildStateFromRow(ctx context.Context, rows *sql.Rows) (*WorkflowBuildState, error) {
	_, span := tracing.Start(ctx)
	defer span.End()

	var webhookDeliveryID sql.NullString
	var imposerRepositoryID int64

	wfBuildState := &WorkflowBuildState{}
	err := rows.Scan(
		&wfBuildState.DatabaseID,
		&wfBuildState.ExecutionID,
		&wfBuildState.CheckSuiteID,
		&wfBuildState.QueuedAt,
		&wfBuildState.StartedAt,
		&wfBuildState.Identifier,
		&wfBuildState.CompletedAt,
		&wfBuildState.ExternalBuildID,
		&wfBuildState.RepositoryID,
		&wfBuildState.CommitSha,
		&wfBuildState.Event,
		&webhookDeliveryID,
		&wfBuildState.State,
		&wfBuildState.WorkflowRunID,
		&wfBuildState.WorkflowRunNumber,
		&wfBuildState.WorkflowFilePath,
		&wfBuildState.WasDelayed,
		&wfBuildState.ActorID,
		&wfBuildState.WorkflowMetadata,
		&imposerRepositoryID,
		&wfBuildState.Backend,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	if webhookDeliveryID.Valid {
		wfBuildState.WebhookDeliveryID = &webhookDeliveryID.String
	}

	if wfBuildState.Event == "" {
		wfBuildState.Event = unknownEvent
	}

	if imposerRepositoryID > 0 {
		wfBuildState.WorkflowFilePath = postProcessWorkflowFilePath(wfBuildState.WorkflowFilePath, imposerRepositoryID)
	}

	return wfBuildState, nil
}

type DataForPrejobtoken struct {
	WorkflowBuildDatabaseID int64
	WorkflowRunID           int64
	Event                   string
	CustomerLabel           string
}

type DataForStatusPostback struct {
	WorkflowBuildDatabaseID          int64
	ExternalBuildID                  string
	CheckSuiteState                  *types.CheckSuiteState
	QueuedAt                         *time.Time
	StartedAt                        *time.Time
	CreatedAt                        time.Time
	WorkflowMetadata                 metadata.WorkflowMetadata
	WasDelayed                       bool
	Rerun                            bool
	Event                            string
	EventTime                        *time.Time
	CompletedAt                      *time.Time
	WorkflowBuildExecutionDatabaseID *int64
	Attempt                          *int64
	GitHubTenantID                   *int64
}

// GetBeginTime attempts to get the beginning time
func (d *DataForStatusPostback) GetBeginTime() time.Time {
	if d.QueuedAt != nil {
		return *d.QueuedAt
	}

	if d.StartedAt != nil {
		return *d.StartedAt
	}

	// Default to the CreatedAt time
	return d.CreatedAt
}

func (d *DataForStatusPostback) GetQueuedAt() time.Time {
	if d.QueuedAt != nil {
		return *d.QueuedAt
	}

	// Default to the CreatedAt time
	return d.CreatedAt
}

func (d *DataForStatusPostback) GetStartedAt() time.Time {
	if d.StartedAt != nil {
		return *d.StartedAt
	}

	// Default to the CreatedAt time
	return d.CreatedAt
}

func (w *workflowBuildsRepository) GetDataForStatusPostback(ctx context.Context, planID string) (*DataForStatusPostback, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `SELECT
			b.id,
			b.repository_id,
			b.commit_sha,
			b.event_ref,
			b.checkout_sha,
			b.checkout_ref,
			b.workflow_id,
			b.workflow_file_path,
			b.workflow_run_id,
			b.check_suite_id,
			b.rerun,
			b.event,
			b.event_time,
			x.id,
			x.external_build_id,
			x.queued_at,
			x.started_at,
			x.created_at,
			x.completed_at,
			x.reporting_metadata,
			x.was_delayed,
			b.imposer_repository_id,
			x.attempt,
			b.github_tenant_id
		FROM workflow_builds AS b
		JOIN workflow_build_executions AS x
			ON b.id = x.workflow_build_id
		WHERE x.plan_id = ?`

	planUUID, err := uuid.Parse(planID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	binaryUUID, err := planUUID.MarshalBinary()
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	rows, err := w.db.QueryContextWith(ctx, query, asql.WithName("GetDataForStatusPostback"), binaryUUID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	defer rows.Close()
	if !rows.Next() {
		return nil, false, nil
	}

	ret := DataForStatusPostback{
		CheckSuiteState: &types.CheckSuiteState{},
	}

	var imposerRepositoryID int64

	if err := rows.Scan(
		&ret.WorkflowBuildDatabaseID,
		&ret.CheckSuiteState.RepositoryID,
		&ret.CheckSuiteState.EventSHA,
		&ret.CheckSuiteState.EventRef,
		&ret.CheckSuiteState.CheckoutSHA,
		&ret.CheckSuiteState.CheckoutRef,
		&ret.CheckSuiteState.FlowIdentifier,
		&ret.CheckSuiteState.WorkflowFilePath,
		&ret.CheckSuiteState.WorkflowRunID,
		&ret.CheckSuiteState.CheckSuiteIDPair.GlobalID,
		&ret.Rerun,
		&ret.Event,
		&ret.EventTime,
		&ret.WorkflowBuildExecutionDatabaseID,
		&ret.ExternalBuildID,
		&ret.QueuedAt,
		&ret.StartedAt,
		&ret.CreatedAt,
		&ret.CompletedAt,
		&ret.WorkflowMetadata,
		&ret.WasDelayed,
		&imposerRepositoryID,
		&ret.Attempt,
		&ret.GitHubTenantID); err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	if rows.Err() != nil {
		return nil, false, tracing.RecordError(span, rows.Err())
	}

	if w.isMultiTenant {
		if ret.GitHubTenantID == nil {
			return nil, false, tracing.RecordError(span, errors.New("github tenant id in workflow build state must not be nil in multi-tenant environment"))
		}
		if _, err := ghtenant.ValidateTenantID(*ret.GitHubTenantID); err != nil {
			return nil, false, tracing.RecordError(span, errors.Wrap(err, "github tenant id in workflow build state must be valid in multi-tenant environment"))
		}
	}

	if imposerRepositoryID > 0 {
		ret.CheckSuiteState.WorkflowFilePath = postProcessWorkflowFilePath(ret.CheckSuiteState.WorkflowFilePath, imposerRepositoryID)
	}

	return &ret, true, nil
}

func (w *workflowBuildsRepository) GetDataForGatePostback(ctx context.Context, externalJobID string) (*DataForGatePostback, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `SELECT
			b.id,
			b.repository_id,
			j.check_run_id,
			b.completed_at,
			x.was_delayed
		FROM workflow_jobs AS j
		JOIN workflow_builds AS b
			ON j.workflow_build_id = b.id
		JOIN workflow_build_executions AS x
			ON b.id = x.workflow_build_id
		WHERE j.external_job_id = ?
		ORDER BY x.id DESC
		LIMIT 1`

	rows, err := w.db.QueryContextWith(ctx, query, asql.WithName("GetDataForGatePostback"), externalJobID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	defer rows.Close()
	if !rows.Next() {
		return nil, false, nil
	}

	ret := DataForGatePostback{}

	if err := rows.Scan(&ret.WorkflowBuildDatabaseID, &ret.RepositoryID, &ret.CheckRunID, &ret.BuildCompletedAt, &ret.WasDelayed); err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	if rows.Err() != nil {
		return nil, false, tracing.RecordError(span, rows.Err())
	}

	return &ret, true, nil
}

func (w *workflowBuildsRepository) GetWaitingOnResourceCheckSuiteID(ctx context.Context, planID string) (*DataForWaitingOnCheckSuiteResource, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var rows *sql.Rows
	var err error
	var ret DataForWaitingOnCheckSuiteResource
	query := `SELECT
			b.check_suite_id,
			b.id
		FROM workflow_builds AS b
		JOIN workflow_build_executions AS x
			ON b.id = x.workflow_build_id
		WHERE x.plan_id = ?`

	planUUID, err := uuid.Parse(planID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	binaryUUID, err := planUUID.MarshalBinary()
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	rows, err = w.db.QueryContextWith(ctx, query, asql.WithName("GetWaitingOnResourceCheckSuiteID"), binaryUUID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	defer rows.Close()

	if !rows.Next() {
		return nil, false, nil
	}

	if err := rows.Scan(&ret.WorkflowBuildCheckSuiteID, &ret.WorkflowBuildDatabaseID); err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	if rows.Err() != nil {
		return nil, false, tracing.RecordError(span, rows.Err())
	}

	return &ret, true, nil
}

func (w *workflowBuildsRepository) GetWaitingOnResourceCheckRunID(ctx context.Context, externalJobID string) (*DataForWaitingOnCheckRunResource, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var rows *sql.Rows
	var err error
	var ret DataForWaitingOnCheckRunResource
	query := `SELECT
			check_run_id,
			workflow_build_id
		FROM workflow_jobs
		WHERE external_job_id = ?`
	rows, err = w.db.QueryContextWith(ctx, query, asql.WithName("GetWaitingOnResourceCheckRunID"), externalJobID)

	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	defer rows.Close()
	if !rows.Next() {
		return nil, false, nil
	}

	if err := rows.Scan(&ret.WorkflowJobCheckRunID, &ret.WorkflowBuildDatabaseID); err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	if rows.Err() != nil {
		return nil, false, tracing.RecordError(span, rows.Err())
	}

	return &ret, true, nil
}

type DataForWaitingOnCheckSuiteResource struct {
	WorkflowBuildCheckSuiteID types.GlobalID
	WorkflowBuildDatabaseID   int64
}

type DataForWaitingOnCheckRunResource struct {
	WorkflowJobCheckRunID   types.GlobalID
	WorkflowBuildDatabaseID int64
}

type DataForGatePostback struct {
	RepositoryID            types.GlobalID
	CheckRunID              string
	BuildCompletedAt        *time.Time
	WorkflowBuildDatabaseID int64
	WasDelayed              bool
}

type DataForSecurityDetails struct {
	WorkflowBuildDatabaseID int64
	RepositoryID            types.GlobalID
	Event                   string
	EventPayload            []byte
	WorkflowMetadata        *metadata.WorkflowMetadata
	GitHubTenantID          *int64
}

type DataForTokenRequest struct {
	RepositoryID     types.GlobalID
	InstallationID   int64
	TokenPermissions *tokens.PermissionSettings
	WorkflowRunID    int64
	WorkflowMetadata *metadata.WorkflowMetadata
	WorkflowFilePath string
	GitHubTenantID   *int64
}

type DataForHealer struct {
	ID               int64
	ExecutionID      int64
	UUID             types.WorkflowExecutionID
	CreatedAt        *time.Time
	RepositoryID     types.GlobalID
	CheckSuiteID     types.GlobalID
	OwnerID          int64
	State            build.WorkflowState
	WorkflowFilePath string
	ExternalBuildID  string
	GitHubTenantID   *int64
}

func (d *DataForSecurityDetails) GetEvent() string {
	return d.Event
}

func (d *DataForSecurityDetails) GetEventPayload() []byte {
	return d.EventPayload
}

func (w *workflowBuildsRepository) GetDataForSecurityDetails(ctx context.Context, planID string) (*DataForSecurityDetails, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `SELECT
			b.id,
			b.repository_id,
			b.event,
			x.reporting_metadata,
			b.github_tenant_id
		FROM workflow_builds AS b
		JOIN workflow_build_executions AS x
			ON b.id = x.workflow_build_id
		WHERE x.plan_id = ?`

	planUUID, err := uuid.Parse(planID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	binaryUUID, err := planUUID.MarshalBinary()
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	wb := &DataForSecurityDetails{}
	err = w.db.QueryScanWith(ctx, query, asql.WithName("GetDataForSecurityDetails"), asql.Params(binaryUUID),
		&wb.WorkflowBuildDatabaseID, &wb.RepositoryID, &wb.Event, &wb.WorkflowMetadata, &wb.GitHubTenantID)
	if err == sql.ErrNoRows {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	wb.EventPayload, err = w.payloads.Get(ctx, wb.WorkflowBuildDatabaseID, wb.RepositoryID)
	if err != nil {
		return nil, false, tracing.RecordError(span, errors.Wrap(err, "error fetching workflow build payload"))
	}

	return wb, true, nil
}

func (w *workflowBuildsRepository) GetDataForPrejobtoken(ctx context.Context, planID string) (*DataForPrejobtoken, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `SELECT
			b.id,
			b.workflow_run_id,
			b.event,
			COALESCE(b.reporting_metadata ->> '$.customer_label', '')
		FROM workflow_builds AS b
		JOIN workflow_build_executions AS x
			ON b.id = x.workflow_build_id
		WHERE x.plan_id = ?`

	planUUID, err := uuid.Parse(planID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	binaryUUID, err := planUUID.MarshalBinary()
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	wb := &DataForPrejobtoken{}
	err = w.db.QueryScanWith(ctx, query, asql.WithName("GetDataForPrejobtoken"), asql.Params(binaryUUID), &wb.WorkflowBuildDatabaseID, &wb.WorkflowRunID, &wb.Event, &wb.CustomerLabel)
	if err == sql.ErrNoRows {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	return wb, true, nil
}

func (w *workflowBuildsRepository) GetWorkflowBuildPayload(ctx context.Context, workflowBuildID int64, repoID types.GlobalID) ([]byte, error) {
	// call through to the payloads DB store
	return w.payloads.Get(ctx, workflowBuildID, repoID)
}

// GetDataForTokenRequest gets data needed to fulfill an API token request.
func (w *workflowBuildsRepository) GetDataForTokenRequest(ctx context.Context, planID string) (*DataForTokenRequest, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	planUUID, err := uuid.Parse(planID)
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	binaryUUID, err := planUUID.MarshalBinary()
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}

	query := `SELECT
			b.repository_id,
			b.token_permissions,
			b.workflow_run_id,
			b.reporting_metadata,
			b.workflow_file_path,
			b.imposer_repository_id,
			b.github_tenant_id
		FROM workflow_builds AS b
		JOIN workflow_build_executions AS x
			ON b.id = x.workflow_build_id
		WHERE x.plan_id = ?`
	wb := &DataForTokenRequest{}
	var imposerRepositoryID int64
	err = w.db.QueryScanWith(ctx, query, asql.WithName("GetDataForTokenRequest"), asql.Params(binaryUUID), &wb.RepositoryID, &wb.TokenPermissions, &wb.WorkflowRunID, &wb.WorkflowMetadata, &wb.WorkflowFilePath, &imposerRepositoryID, &wb.GitHubTenantID)
	if err == sql.ErrNoRows {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, tracing.RecordError(span, err)
	}
	if w.isMultiTenant {
		if wb.GitHubTenantID == nil {
			return nil, false, tracing.RecordError(span, errors.New("github tenant id in workflow build state must not be nil in multi-tenant environment"))
		}
		if _, err := ghtenant.ValidateTenantID(*wb.GitHubTenantID); err != nil {
			return nil, false, tracing.RecordError(span, errors.Wrap(err, "github tenant id in workflow build state must be valid in multi-tenant environment"))
		}
	}

	if imposerRepositoryID > 0 {
		wb.WorkflowFilePath = postProcessWorkflowFilePath(wb.WorkflowFilePath, imposerRepositoryID)
	}

	return wb, true, nil
}

const (
	// This is the maximum number of records we'll return at once to the
	// caller that is responsible for actually healing each workflow
	RecordLimit = 50000

	// Number of seconds after which the deadline context being used
	// for the build healing query expires
	ContextClampThreshold = 6 * time.Second
)

func (w *workflowBuildsRepository) GetWorkflowsToHeal(ctx context.Context, from, to time.Duration) ([]DataForHealer, bool, error) {
	query := `
	SELECT
		b.id,
		x.id,
		x.plan_id,
		x.created_at,
		b.repository_id,
		b.check_suite_id,
		b.reporting_metadata -> '$.repositoryOwner.id' as owner_id,
		x.state,
		b.workflow_file_path,
		b.imposer_repository_id,
		x.external_build_id,
		b.github_tenant_id
	FROM workflow_build_executions AS x
	JOIN workflow_builds AS b
		ON b.id = x.workflow_build_id
	WHERE x.created_at >= UTC_TIMESTAMP() - INTERVAL ? HOUR
	AND x.created_at < UTC_TIMESTAMP() - INTERVAL ? HOUR
	AND x.state IN (0,1,2)
	AND x.completed_at IS NULL
	AND x.backend = ?
	LIMIT ?`

	var imposerRepositoryID int64
	var ownerID sql.NullInt64
	var result []DataForHealer
	var rows *sql.Rows
	var err error

	// If the FF is enabled, replace the normal context with a deadline context that kills querying operations after
	// 6 seconds. See the implementation of IsFeatureEnabledForActor to understand why we pass in types.NilGlobalID
	if w.gidMigrator.IsFeatureEnabledForActor(ctx, github.ClampBuildHealingQueriesAfter6Seconds, types.NilGlobalID) {
		expiringCtx, cancel := context.WithTimeoutCause(ctx, ContextClampThreshold, errors.Errorf("query exceeded %d second threshold", ContextClampThreshold))
		rows, err = w.db.QueryContextWith(expiringCtx, query, asql.WithName("GetWorkflowsToHeal"), int(from.Hours()), int(to.Hours()), types.WorkflowBackendActionsService, RecordLimit)

		defer cancel()
	} else {
		rows, err = w.db.QueryContextWith(ctx, query, asql.WithName("GetWorkflowsToHeal"), int(from.Hours()), int(to.Hours()), types.WorkflowBackendActionsService, RecordLimit)
	}

	if err != nil && err != sql.ErrNoRows {
		w.logger.Error(ctx, "workflow healing query error", kvp.Err(err))
		return nil, false, err
	} else if err == sql.ErrNoRows {
		// sql.ErrNoRows is not a true error condition in this context
		w.logger.Log(ctx, "workflow healing query found no builds to heal")
	} else {
		w.logger.Log(ctx, "workflow healing query found builds to heal")
	}

	if rows != nil {
		for rows.Next() {
			var row DataForHealer
			err := rows.Scan(
				&row.ID,
				&row.ExecutionID,
				&row.UUID,
				&row.CreatedAt,
				&row.RepositoryID,
				&row.CheckSuiteID,
				&ownerID,
				&row.State,
				&row.WorkflowFilePath,
				&imposerRepositoryID,
				&row.ExternalBuildID,
				&row.GitHubTenantID,
			)
			if err != nil {
				w.logger.Error(ctx, "workflow healing row scanning error", kvp.Err(err))
				// healing is "best effort"; one row scanning error shouldn't cause
				// the job to exit early
				continue
			}

			if imposerRepositoryID > 0 {
				row.WorkflowFilePath = postProcessWorkflowFilePath(row.WorkflowFilePath, imposerRepositoryID)
			}

			if ownerID.Valid && ownerID.Int64 > 0 {
				row.OwnerID = ownerID.Int64
			} else {
				row.OwnerID = 0
			}

			result = append(result, row)
		}

		if rows.Err() != nil {
			w.logger.Error(ctx, "workflow healing row iteration error", kvp.Err(rows.Err()))
		}

		defer rows.Close()
	}

	w.logger.Log(ctx, "returning workflows to heal", kvp.Int("gh.launch.workflows.count", len(result)))
	return result, true, nil
}

func wrapNullString(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}

	return sql.NullString{
		String: s,
		Valid:  true,
	}
}

func wrapNullInt64(i int64) sql.NullInt64 {
	if i <= 0 {
		return sql.NullInt64{}
	}

	return sql.NullInt64{
		Int64: i,
		Valid: true,
	}
}

func (w *workflowBuildsRepository) logGlobalIDReplacement(ctx context.Context, operation, field string, legacyGID, nextGID types.GlobalID) {
	w.stats.Counter(ctx, "global_ids.replace_wfb_legacy_gid", statter.Tags{"operation": operation, "column": field}, 1)
	w.logger.Debug(ctx, "Replacing legacy global id with next value for workflow_builds column",
		kvp.String("gh.launch.column", field),
		kvp.String("gh.launch.legacy_global_id", legacyGID.String()),
		kvp.String("gh.launch.next_global_id", nextGID.String()))
}

// This is done to pull out metadata before storing in workflow_builds
// in case of required workflows.
//
// This should have no effect on non required workflows
func preProcessWorkflowFilePath(path string) (int64, string, error) {
	if !requiredworkflowutils.IsRequiredWorkflow(path) {
		return 0, path, nil
	}

	imposerRepositoryID, workflowFilePath, err := requiredworkflowutils.ExtractAndRemoveMetadataFromRequiredWorkflowPath(path)
	if err != nil {
		return 0, "", err
	}

	return imposerRepositoryID, workflowFilePath, nil
}

// We construct back the metadata in case of required workflows
func postProcessWorkflowFilePath(path string, sourceRepoID int64) string {
	return requiredworkflowutils.ConstructRequiredWorkflowPath(path, sourceRepoID)
}

func trimVarCharColumnData(original string, limit int) string {
	// This can be switched to built-in 'min' function after we are using Go 1.21
	if len(original) < limit {
		limit = len(original)
	}
	return strings.ToValidUTF8(original[:limit], "")
}

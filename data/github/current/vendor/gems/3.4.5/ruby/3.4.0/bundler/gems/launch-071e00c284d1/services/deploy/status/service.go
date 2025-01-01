// Package status handles postbacks
package status

import (
	"context"
	http "net/http"
	strconv "strconv"
	"strings"
	"time"

	"github.com/github/go-kvp"
	"github.com/golang/protobuf/ptypes/empty"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/google/uuid"
	errs "github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	entities "github.com/github/launch/hydro/schemas/github/v1/entities"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/graphqlid"
	"github.com/github/launch/workflowbuild/build"
)

// Generate a mock for the Twirp generated interface.
type Hydro interface {
	EmitWorkflowExecution(execution *hydroV0.WorkflowExecution)
	EmitJobExecution(execution *hydroV0.JobExecution)
	CountErroredEvent(eventType string)
	EmitWorkflowUpdateEvent(ctx context.Context, evt *hydroV0.WorkflowUpdate) error
}

type service struct {
	log                  logs
	stats                statter.Statter
	azpResourcesRepo     deployer.AzpResourcesRepository
	buildRepo            deployer.WorkflowBuildsRepository
	jobsRepo             deployer.JobsRepository
	ghClientFactory      github.Factory
	githubTwirpClient    ghtwirp.Client
	azpClientFactory     azp.RepositoryClientFactory
	hydro                Hydro
	aqueductClient       aqueduct.Client
	environment          string
	labLogger            logs
	makeStatusClient     func(ctx context.Context, s *service, repoConfig *repoConfig) statusClient
	makeSyncStatusClient func(ctx context.Context, s *service, repositoryID types.GlobalID, workflowID string) syncStatusClient
	makeUsageClient      func(ctx context.Context, s *service) usageClient
	isMultitenant        bool
}

type logs interface {
	Log(ctx context.Context, msg string, fields ...kvp.Field)
	Debug(ctx context.Context, msg string, fields ...kvp.Field)
	Report(ctx context.Context, err error, fields ...kvp.Field)
	Error(ctx context.Context, msg string, fields ...kvp.Field)
}

// makeUsageClient returns a UsageClient that either directs usage traffic to JobExecution
// or the Results service based on the feature flag.
func makeUsageClient(ctx context.Context, svc *service) usageClient {
	if launchconfig.UsingResultsService() {
		svc.log.Debug(ctx, "Using the results service for usage")
		return newResultsUsageClient(svc.aqueductClient, svc.log)
	}

	svc.log.Debug(ctx, "Communicating directly with dotcom for usage")
	return newHydroUsageClient(svc.hydro, svc.log)
}

// JobStatus and RunStatus use a different github.Client than GateStatus, which is what the configs are used for
func makeStatusClient(ctx context.Context, svc *service, repoConfig *repoConfig) statusClient {
	if launchconfig.UsingResultsService() {
		svc.log.Debug(ctx, "using results service")
		return newResultsStatusClient(svc.aqueductClient, svc.log)
	}

	svc.log.Debug(ctx, "using graphql postbacks")
	return newGraphQLStatusClient(
		svc.log,
		svc.labLogger,
		clientConfig{
			repoConfig:    repoConfig,
			ghFactory:     svc.ghClientFactory,
			ghTwirpClient: svc.githubTwirpClient,
		},
		svc.stats,
		svc.isMultitenant,
	)
}

//nolint:unparam // repositoryID isn't used currently, but it may be used in the future for FFs
func makeSyncStatusClient(_ context.Context, svc *service, _ types.GlobalID, workflowID string) syncStatusClient {
	// since this is sync for getting check run data back, this would not apply to the hydro client
	return newGraphQLStatusClient(
		svc.log,
		svc.labLogger,
		clientConfig{
			repoConfig: &repoConfig{
				workflowID: workflowID,
				buildRepo:  svc.buildRepo,
			},
			ghFactory:     svc.ghClientFactory,
			ghTwirpClient: svc.githubTwirpClient,
		},
		svc.stats,
		svc.isMultitenant,
	)
}

func New(log logs, statter statter.Statter, azpResourcesRepo deployer.AzpResourcesRepository, buildRepo deployer.WorkflowBuildsRepository, jobsRepo deployer.JobsRepository, ghClientFactory github.Factory, githubTwirpClient ghtwirp.Client, azpClientFactory azp.RepositoryClientFactory, isLab bool, emitter Hydro, aqueductClient aqueduct.Client, environment string, isMultitenant bool) *service {
	var labLogger logs = logger.NullLogger()
	if isLab {
		labLogger = log
	}
	return &service{
		log:                  log,
		labLogger:            labLogger,
		stats:                statter,
		azpResourcesRepo:     azpResourcesRepo,
		buildRepo:            buildRepo,
		jobsRepo:             jobsRepo,
		ghClientFactory:      ghClientFactory,
		githubTwirpClient:    githubTwirpClient,
		azpClientFactory:     azpClientFactory,
		hydro:                emitter,
		aqueductClient:       aqueductClient,
		environment:          environment,
		makeStatusClient:     makeStatusClient,
		makeSyncStatusClient: makeSyncStatusClient,
		makeUsageClient:      makeUsageClient,
		isMultitenant:        isMultitenant,
	}
}

// EventableError is an error that is returned for something going wrong related
// to Hydro events.
type EventableError struct {
	err             error
	shouldEmitEvent bool
}

// NewEventableError returns a new instance of EventableError.
func NewEventableError(err error, shouldEmitEvent bool) *EventableError {
	return &EventableError{
		err:             err,
		shouldEmitEvent: shouldEmitEvent,
	}
}

// Error returns the underlying error string.
func (e *EventableError) Error() string {
	return e.err.Error()
}

// Cause returns the wrapped error.
func (e *EventableError) Cause() error {
	return e.err
}

// Unwrap provides compatibility for Go 1.13 error chains.
func (e *EventableError) Unwrap() error {
	return e.err
}

// WaitingOn is the collection of ID references for blocking resources in concurrency groups
// https://docs.github.com/actions/using-jobs/using-concurrency
type WaitingOn struct {
	CheckSuiteID types.GlobalID
	CheckRunID   types.GlobalID
}

// JobStatus receives a JobStatusRequest from launch-receiver, and processes it, including finding
// it in the DB, and then updating the DB and CheckRuns appropriately.
func (s *service) JobStatus(ctx context.Context, req *JobStatusRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.launch.workflow.id", req.GetWorkflowId()),
		attribute.String("gh.launch.job.id", req.GetJobId()),
		attribute.String("gh.launch.job.runtime", req.GetRuntime()),
		attribute.Bool("gh.launch.self_hosted", req.GetSelfHosted()),
	))
	defer span.End()

	span.AddEvent("job status duration", trace.WithAttributes(
		attribute.Int64("gh.launch.duration_ms", req.GetDurationMs())),
	)

	dbData, isDisabled, err := s.handleJobStatusRequest(ctx, req)
	if err != nil {
		// Just in case there's an upstream error from graphql or Twirp, let's fallback to
		// checking this request error as a just in case.
		if errors.IsNotFoundError(err) {
			return nil, svcerr.NewNotFoundError("Check run or repository not found")
		}

		if reqErr := errors.GetHTTPError(err); reqErr != nil {
			// When fetching the repository installation we may receive:
			// 	 403 - if the repo has been archived
			//   404 - if the repo has been archived and deleted (handled above)
			// Return a NotFoundError so receiver can return a 404
			if reqErr.MatchStatusCodes(http.StatusForbidden) {
				return nil, svcerr.NewNotFoundError("Could not apply status - 403 response")
			}
		}

		if err == ErrPostbackDenied {
			s.log.Report(ctx, err)
			return nil, err
		}

		s.handleEmissionError(ctx, err, events.JobExecutionEvent,
			jobLogFields(req)...,
		)

		s.log.Report(ctx, err)
		span.RecordError(err)
		return nil, svcerr.NewInternalError("Could not apply status")
	}
	if isDisabled {
		s.log.Debug(ctx, "skipping job status postback because spammy/archived/deleted repository found")
		return nil, svcerr.NewPermissionDeniedError("Could not apply status")
	}

	s.log.Log(ctx, "Updated check run from post-back",
		kvp.String("gh.check_suite.external_id", req.GetWorkflowId()),
		kvp.String("gh.check_suite.global_id", dbData.CheckSuiteState.CheckSuiteIDPair.GlobalID.String()),
	)

	return &empty.Empty{}, nil
}

func jobLogFields(req *JobStatusRequest) []kvp.Field {
	return []kvp.Field{
		kvp.String("gh.launch.workflow.identifier", req.GetWorkflowId()),
		kvp.String("gh.launch.job.id", req.GetJobId()),
		kvp.String("gh.launch.job.runtime", req.GetRuntime()),
		kvp.Bool("gh.launch.self_hosted", req.GetSelfHosted()),
		kvp.Int64("gh.launch.duration_ms", req.GetDurationMs()),
	}
}

// RunStatus receives a RunStatusRequest from launch-receiver, and processes it, including finding
// it in the DB, and then updating the DB and CheckSuites appropriately.
func (s *service) RunStatus(ctx context.Context, req *RunStatusRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.check_suite.external_id", req.WorkflowId),
	))
	defer span.End()

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.check_suite.external_id", req.GetWorkflowId()))
	dbData, isDisabled, err := s.handleRunStatusRequest(ctx, req)
	if err != nil {
		// Just in case there's an upstream error from graphql or Twirp, let's fallback to
		// checking this request error as a just in case.
		if errors.IsNotFoundError(err) {
			return nil, svcerr.NewNotFoundError("Check suite or repository not found")
		}

		if reqErr := errors.GetHTTPError(err); reqErr != nil {
			// When fetching the repository installation we may receive:
			//   403 - if the repo has been archived
			//   404 - if the repo has been archived and deleted (handled above)
			// Return a NotFoundError so receiver can return a 404
			if reqErr.MatchStatusCodes(http.StatusForbidden) {
				return nil, svcerr.NewNotFoundError("Could not apply status - 403 response")
			}
		}

		if err == ErrPostbackDenied {
			s.log.Report(ctx, err)
			return nil, err
		}

		s.handleEmissionError(ctx, err, events.WorkflowExecutionEvent, kvp.String("gh.launch.workflow.identifier", req.GetWorkflowId()))
		s.log.Report(ctx, err)
		span.RecordError(err)
		return nil, svcerr.NewInternalError("Could not apply run status")
	}
	// isDisabled is true when the repository is archived, spammy, or deleted.
	// So we return a 404 in this case.
	if isDisabled {
		s.log.Debug(ctx, "skipping run status postback because spammy/archived/deleted repository found")
		return nil, svcerr.NewPermissionDeniedError("Could not apply status")
	}

	s.log.Log(ctx, "Updated check suite from post-back",
		kvp.String("gh.check_suite.global_id", dbData.CheckSuiteState.CheckSuiteIDPair.GlobalID.String()),
	)

	return &empty.Empty{}, nil
}

// GateStatus receives a GateStatusRequest from launch-receiver, and processes it
func (s *service) GateStatus(ctx context.Context, req *GateStatusRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.launch.gate.global_id", req.GetGateId()),
		attribute.Bool("gh.launch.gate.open", req.IsOpen),
		attribute.Bool("gh.launch.gate.concluded", req.IsConcluded),
	))
	defer span.End()

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.gate.global_id", req.GetGateId()))

	dbData, exists, err := s.buildRepo.GetDataForGatePostback(ctx, req.GetExternalId())
	if err != nil {
		s.log.Report(ctx, err)
		return nil, svcerr.NewInternalError("Error finding check run id and installation id for gate")
	}
	if !exists {
		return nil, svcerr.NewNotFoundError("Workflow run identified by external ID does not exist")
	}

	if !dbData.WasDelayed && !req.IsOpen {
		err = s.buildRepo.SetWasDelayed(ctx, dbData.WorkflowBuildDatabaseID)
		if err != nil {
			return nil, svcerr.NewInternalError("Could not set the workflow run as delayed")
		}
	}

	if dbData.BuildCompletedAt != nil {
		// Postback should only work when runs are in progress.
		return nil, ErrPostbackDenied
	}

	// UpdateGateStatus only uses a repository owner client, which does not require repoConfig
	statusClient := s.makeStatusClient(ctx, s, nil)

	if err := statusClient.UpdateGateStatus(ctx, req, UpdateGateStatusParams{
		RepositoryID: dbData.RepositoryID,
		CheckRunID:   types.NewGlobalID(ctx, dbData.CheckRunID),
	}); err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "updating gate status"))
	}

	s.log.Log(ctx, "Updated gate from post-back")

	return &empty.Empty{}, nil
}

//gocyclo:ignore
func (s *service) handleJobStatusRequest(ctx context.Context, update *JobStatusRequest) (*deployer.DataForStatusPostback, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	s.log.Debug(ctx, "proccessing job status request")

	completePostback := update.GetComplete()

	shouldEmitEvent := shouldEmitEvent(update)

	dbData, ok, err := s.buildRepo.GetDataForStatusPostback(ctx, update.WorkflowId)
	if err != nil {
		return nil, false, tracing.RecordError(span, NewEventableError(errs.Wrap(err, "db error retrieving data for job status"), shouldEmitEvent))
	}
	if !ok {
		return nil, false, tracing.RecordError(span, NewEventableError(errs.New("could not find row for job status"), shouldEmitEvent))
	}

	if dbData.CompletedAt != nil {
		// Postback should only work when runs are in progress.
		return nil, false, ErrPostbackDenied
	}

	var tenantID int64
	if dbData.GitHubTenantID != nil {
		tenantID = *dbData.GitHubTenantID
	}

	ctx, err = ghtenant.ContextWithTenantID(ctx, tenantID, launchconfig.IsMultiTenant())
	if err != nil {
		return nil, false, tracing.RecordError(span, NewEventableError(errs.Wrap(err, "error setting github tenant in current context"), shouldEmitEvent))
	}

	var status string
	if completePostback != nil {
		status = "completed"
	} else {
		status = "in_progress"
	}

	spanTags := []attribute.KeyValue{
		attribute.String("gh.launch.resolved_commit.sha", dbData.CheckSuiteState.EventSHA.String()),
		attribute.String("gh.check_suite.global_id", dbData.CheckSuiteState.CheckSuiteIDPair.GlobalID.String()),
		attribute.String("gh.launch.workflow.identifier", dbData.CheckSuiteState.WorkflowFilePath),
		attribute.String("gh.repo.global_id", dbData.CheckSuiteState.RepositoryID.String()),
		attribute.String("gh.launch.job.status", status),
	}

	logFields := []kvp.Field{
		kvp.Any("gh.launch.resolved_commit.sha", dbData.CheckSuiteState.EventSHA),
		kvp.String("gh.check_suite.global_id", dbData.CheckSuiteState.CheckSuiteIDPair.GlobalID.String()),
		kvp.String("gh.launch.workflow.identifier", dbData.CheckSuiteState.WorkflowFilePath),
		kvp.String("gh.repo.global_id", dbData.CheckSuiteState.RepositoryID.String()),
		kvp.String("gh.launch.job.status", status),
	}

	isRepoDeleted := s.checkRepoDeletedState(ctx, dbData, update.WorkflowId)
	if isRepoDeleted {
		spanTags = append(spanTags, attribute.Bool("gh.repo.is_deleted", isRepoDeleted))
		logFields = append(logFields, kvp.Bool("gh.repo.is_deleted", isRepoDeleted))
	}

	span.SetAttributes(spanTags...)

	ctx = ctxstash.WithFields(ctx, logFields...)

	if !isRepoDeleted {
		isDisabled, err := s.githubTwirpClient.IsRepositoryActionsDisabled(ctx, dbData.CheckSuiteState.RepositoryID)
		if err != nil {
			s.log.Report(ctx, errs.Wrap(err, "Error checking if repository is disabled"))
		} else if isDisabled {
			return nil, isDisabled, nil
		}
	}

	// We transition the workflow run to started whenever we first see a job that has been started.
	// If the run hasn't set their startedAt attribute we can assume the run has not started.
	if dbData.StartedAt == nil {
		inProgressUpdate := update.GetInProgress()
		var azStartedAt time.Time
		if inProgressUpdate != nil && inProgressUpdate.StartedAt != nil {
			azStartedAt = inProgressUpdate.StartedAt.AsTime()
		} else if completePostback != nil && completePostback.StartedAt != nil {
			azStartedAt = completePostback.StartedAt.AsTime()
		}

		// Actions service sends a started at when the job is in any state except NotStarted
		// We can set the run to started at even if the first job returns with a started_at time.
		// This also will mark the job as started even if the first job we get back is "skipped"
		if !azStartedAt.IsZero() && err == nil {
			err = s.handleRunStarted(ctx, dbData)
			if err != nil {
				return nil, false, tracing.RecordError(span, NewEventableError(err, shouldEmitEvent))
			}
		}
	}

	if !dbData.WasDelayed && update.Delayed {
		err = s.buildRepo.SetWasDelayed(ctx, dbData.WorkflowBuildDatabaseID)
		if err != nil {
			return nil, false, tracing.RecordError(span, NewEventableError(errs.Wrap(err, "db setting the workflow run as delayed"), shouldEmitEvent))
		}
	}

	statusClient := s.makeStatusClient(ctx, s, &repoConfig{
		workflowID: update.GetWorkflowId(),
		buildRepo:  s.buildRepo,
	})

	workflowJob, err := s.jobsRepo.GetWorkflowJobFromJobID(ctx, update.WorkflowId, update.JobId)
	if err != nil {
		return nil, false, tracing.RecordError(span, NewEventableError(errs.Wrap(err, "Error loading workflowJobID"), shouldEmitEvent))
	}
	// handleFirstJobStatusRequest depends on synchronous GraphQL calls to create the workflow job and deal with billing.
	// Since this is an exception, we won't be publishing hydro messages but will continue to use GraphQL for now.
	if workflowJob == nil {
		if shouldEmitEvent && isRepoDeleted {
			// https://github.com/github/c2c-actions-checks/issues/405
			// emit Hydro Billing with the minimum data we have although this scenario occurring is very unlikely.
			s.emitJobExecution(ctx, dbData, 0, 0, update, completePostback, false)
		} else {
			var syncClient syncStatusClient
			if sc, ok := statusClient.(syncStatusClient); ok {
				// if the current status client can be used as a sync client, reuse it
				syncClient = sc
			} else {
				// otherwise initialize a sync client that can handle the check run create
				syncClient = s.makeSyncStatusClient(ctx, s, dbData.CheckSuiteState.RepositoryID, update.GetWorkflowId())
			}

			err := s.handleFirstJobStatus(ctx, update, dbData, syncClient, completePostback, shouldEmitEvent)
			if err != nil {
				return nil, false, tracing.RecordError(span, NewEventableError(err, shouldEmitEvent))
			}
		}
		return dbData, false, nil
	}

	if shouldEmitEvent {
		checkRunID, err := graphqlid.DecodeInt64ID(workflowJob.CheckRunID.String())
		if err == nil {
			s.emitJobExecution(ctx, dbData, workflowJob.ID, checkRunID, update, completePostback, workflowJob.BillingChecked)
		} else {
			s.handleEmissionError(ctx, NewEventableError(err, shouldEmitEvent),
				events.JobExecutionEvent,
				jobLogFields(update)...,
			)
			s.log.Report(ctx, errs.Wrap(err, "Could not decode check run ID to emit JobExecution hydro"))
		}
	}

	logFields = append(logFields,
		kvp.String("gh.check_run.global_id", workflowJob.CheckRunID.String()),
		kvp.Int("gh.launch.job_labels_count", len(update.Labels)),
		kvp.Int64("gh.actions.runner.id", update.RunnerId),
		kvp.String("gh.actions.runner.name", update.RunnerName),
		kvp.Int64("gh.actions.runner_group.id", update.RunnerGroupId),
		kvp.String("gh.actions.runner_group.name", update.RunnerGroupName),
	)

	if isRepoDeleted {
		s.log.Debug(ctx, "skipped updating check run because repo has been deleted", logFields...)
		return dbData, false, nil
	}

	// handle statuses for jobs we've seen before
	ctx = ctxstash.WithFields(ctx, kvp.Int("gh.launch.annotation_count", len(update.GetAnnotations())))
	s.log.Debug(ctx, "updating check run", logFields...)

	waitingOn, err := s.getWaitingOn(ctx, update.Concurrency, dbData.WorkflowBuildDatabaseID)
	if err != nil {
		return nil, false, tracing.RecordError(span, errs.Wrap(err, "getting info on checkrun to wait for"))
	}

	err = statusClient.UpdateCheckRun(ctx, update, UpdateCheckRunParams{CheckSuiteState: dbData.CheckSuiteState, WaitingOn: waitingOn, CheckRunID: workflowJob.CheckRunID})
	if err != nil {
		return nil, false, tracing.RecordError(span, errs.Wrap(err, "updating check run"))
	}

	err = s.jobsRepo.TouchWorkflowJob(ctx, workflowJob.ID)
	if err != nil {
		return nil, false, tracing.RecordError(span, errs.Wrap(err, "touching workflow_job"))
	}

	return dbData, false, nil
}

func shouldEmitEvent(update *JobStatusRequest) bool {
	// Only emit events for completed jobs
	if update.GetComplete() == nil {
		return false
	}

	// Don't emit events for cloned jobs (from a rerun), as this means the job did not actually run (it ran previously)
	if update.IsClonedFromPreviousRun {
		return false
	}

	// We only want to send the event if the runtime information is present
	// When it's present, we know the job is completed.
	// SelfHosted is part of the runtime info. When present we know the job is done,
	// so we can send the event for self hosted runs
	// https://github.com/github/pe-actions-service/issues/207
	return update.GetRuntime() != "" || update.GetSelfHosted()
}

func (s *service) handleFirstJobStatus(ctx context.Context, update *JobStatusRequest, dbData *deployer.DataForStatusPostback, statusClient syncStatusClient, completePostback *JobComplete, shouldEmitEvent bool) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	s.log.Log(ctx, "creating check run")

	waitingOn, err := s.getWaitingOn(ctx, update.Concurrency, dbData.WorkflowBuildDatabaseID)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "Error getting WaitingOn data"))
	}

	idPair, err := statusClient.CreateCheckRun(ctx, update, CreateCheckRunParams{CheckSuiteState: dbData.CheckSuiteState, WaitingOn: waitingOn})
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "unable to create check run"))
	}
	if idPair.IsZeroValue() {
		return tracing.RecordError(span, errs.New("CheckRunIDPair not found in output"))
	}
	s.log.Log(ctx, "created check run",
		kvp.String("gh.check_run.global_id", idPair.GlobalID.String()),
		kvp.Int("gh.check_run.id", int(idPair.DatabaseID)),
	)

	jobID, err := s.jobsRepo.CreateWorkflowJob(ctx, dbData.WorkflowBuildDatabaseID, update.WorkflowId, update.JobId, idPair.GlobalID, dbData.WorkflowBuildExecutionDatabaseID)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "Error writing local workflow_job"))
	}

	if launchconfig.UsingResultsService() {
		s.log.Debug(ctx, "Now sending the results of CreateCheckRun to the results service")

		resultsSyncClient := newResultsSyncClient(s.aqueductClient, s.log, s.githubTwirpClient)

		workflowRunBackendID := update.GetWorkflowId()
		workflowJobRunBackendID := update.GetExternalId()
		dotcomRepoID := dbData.CheckSuiteState.RepositoryID

		err := resultsSyncClient.CreateCheckRun(ctx, workflowRunBackendID, workflowJobRunBackendID, dotcomRepoID, update.DisplayName, idPair.DatabaseID)

		if err != nil {
			s.log.Error(ctx, "Error sending results of CreateCheckRun to the results service", kvp.Err(err))
		}
	}

	if shouldEmitEvent {
		// We haven't done the billing check at this point, but we default to `true` because we want the user to be charged
		// unless billing fails. In this case billing hasn't failed, because we haven't made any call, so we send `true`
		billingChecked := true
		s.emitJobExecution(ctx, dbData, jobID, idPair.DatabaseID, update, completePostback, billingChecked)
	}

	return nil
}

func (s *service) handleRunStarted(ctx context.Context, dbData *deployer.DataForStatusPostback) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	_, err := s.recordStarted(ctx, dbData.WorkflowBuildDatabaseID)
	if err != nil {
		return tracing.RecordError(span, err)
	}
	return nil
}

func (s *service) emitJobExecution(ctx context.Context, dbData *deployer.DataForStatusPostback, jobID int64, checkRunID int64, update *JobStatusRequest, complete *JobComplete, billingChecked bool) {
	_, span := tracing.Start(ctx)
	defer span.End()

	usageClient := s.makeUsageClient(ctx, s)

	err := usageClient.EmitUsage(
		ctx,
		dbData,
		jobID,
		checkRunID,
		update,
		complete,
		billingChecked,
	)

	if err != nil {
		s.log.Error(ctx, "Error emitting usage", kvp.Err(err))
	}
}

func castRunnerType(runnerType string) hydroV0.JobExecution_RunnerType {
	switch strings.ToLower(runnerType) {
	case "self_hosted":
		return hydroV0.JobExecution_RUNNER_TYPE_SELF_HOSTED
	case "hosted":
		return hydroV0.JobExecution_RUNNER_TYPE_HOSTED
	case "custom":
		return hydroV0.JobExecution_RUNNER_TYPE_CUSTOM
	default:
		return hydroV0.JobExecution_RUNNER_TYPE_UNKNOWN
	}
}

func castRuntime(runtime string) hydroV0.JobExecution_Runtime {
	switch strings.ToLower(runtime) {
	case "macos":
		return hydroV0.JobExecution_MACOS
	case "windows":
		return hydroV0.JobExecution_WINDOWS
	case "ubuntu":
		return hydroV0.JobExecution_UBUNTU
	default:
		return hydroV0.JobExecution_RUNTIME_UNKNOWN
	}
}

func castVisibility(visibility entities.Repository_Visibility) hydroV0.JobExecution_Visibility {
	// unfortunately JobExecution.Visibility used its own enum rather than referencing Repository.Visibility - they're
	// in the same order so just cast
	return hydroV0.JobExecution_Visibility(visibility)
}

func (s *service) recordStarted(ctx context.Context, workflowDbID int64) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	transitioned, err := s.buildRepo.TransitionTo(ctx, workflowDbID, build.WorkflowStateStarted)
	if err != nil {
		return false, tracing.RecordError(span, err)
	}

	if transitioned {
		s.stats.Counter(ctx, metrickeys.BuildState, map[string]string{
			metrickeys.Provider: metrickeys.ActionsService,
			metrickeys.State:    metrickeys.BuildWorking,
		}, 1)
	}

	return transitioned, nil
}

func (s *service) handleRunStatusRequest(ctx context.Context, req *RunStatusRequest) (*deployer.DataForStatusPostback, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	dbData, ok, err := s.buildRepo.GetDataForStatusPostback(ctx, req.GetWorkflowId())
	if err != nil {
		return nil, false, NewEventableError(errs.Wrap(err, "error retrieving build row for run status"), true)
	}
	if !ok {
		return nil, false, NewEventableError(errs.New("could not find build row for run status"), true)
	}

	if dbData.CompletedAt != nil {
		// Postback should only work when runs are in progress or not started.
		return nil, false, ErrPostbackDenied
	}

	var tenantID int64
	if dbData.GitHubTenantID != nil {
		tenantID = *dbData.GitHubTenantID
	}

	ctx, err = ghtenant.ContextWithTenantID(ctx, tenantID, launchconfig.IsMultiTenant())
	if err != nil {
		return nil, false, tracing.RecordError(span, NewEventableError(errs.Wrap(err, "error setting github tenant in current context"), true))
	}

	spanTags := []attribute.KeyValue{
		attribute.String("gh.launch.resolved_commit.sha", dbData.CheckSuiteState.EventSHA.String()),
		attribute.String("gh.check_suite.global_id", dbData.CheckSuiteState.CheckSuiteIDPair.GlobalID.String()),
		attribute.String("gh.repo.global_id", dbData.CheckSuiteState.RepositoryID.String()),
		attribute.String("gh.launch.workflow.identifier", dbData.CheckSuiteState.WorkflowFilePath),
		attribute.String("gh.launch.workflow_run.status", "completed"),
	}

	logFields := []kvp.Field{
		kvp.Any("gh.launch.resolved_commit.sha", dbData.CheckSuiteState.EventSHA),
		kvp.String("gh.check_suite.global_id", dbData.CheckSuiteState.CheckSuiteIDPair.GlobalID.String()),
		kvp.String("gh.repo.global_id", dbData.CheckSuiteState.RepositoryID.String()),
		kvp.String("gh.launch.workflow.identifier", dbData.CheckSuiteState.WorkflowFilePath),
		kvp.String("gh.launch.workflow_run.status", "completed"),
	}

	isRepoDeleted := s.checkRepoDeletedState(ctx, dbData, req.WorkflowId)
	if isRepoDeleted {
		spanTags = append(spanTags, attribute.Bool("gh.repo.is_deleted", isRepoDeleted))
		logFields = append(logFields, kvp.Bool("gh.repo.is_deleted", isRepoDeleted))
	}

	span.SetAttributes(spanTags...)

	ctx = ctxstash.WithFields(ctx, logFields...)

	if dbData.QueuedAt == nil && dbData.StartedAt == nil {
		s.log.Error(ctx, "queued_at or started_at was never set")
	}

	beganAt := dbData.GetBeginTime()
	beginTime := timestamppb.New(beganAt)

	// Get completedAt from Postback request data
	completedAt := req.GetComplete().GetCompletedAt()

	s.emitWorkflowExecution(beginTime, completedAt, dbData, dbData.WorkflowMetadata, mapExecutionConclusion(req))

	// https://github.com/github/c2c-actions-checks/issues/405
	// Prevent error from dotcom call failures when repo has been deleted
	if !isRepoDeleted {
		isDisabled, err := s.githubTwirpClient.IsRepositoryActionsDisabled(ctx, dbData.CheckSuiteState.RepositoryID)
		if err != nil {
			s.log.Report(ctx, errs.Wrap(err, "Error checking if repository is disabled"))
		} else if isDisabled {
			span.SetAttributes(attribute.Bool("gh.repos.actions.is_disabled", true))
			return nil, isDisabled, nil
		}

		waitingOn, err := s.getWaitingOn(ctx, req.Concurrency, dbData.WorkflowBuildDatabaseID)
		if err != nil {
			return nil, false, errs.Wrap(err, "Error getting WaitingOn data")
		}

		statusClient := s.makeStatusClient(ctx, s, &repoConfig{
			workflowID: req.GetWorkflowId(),
			buildRepo:  s.buildRepo,
		})

		if err := statusClient.UpdateCheckSuite(ctx, req, UpdateCheckSuiteParams{CheckSuiteState: dbData.CheckSuiteState, WaitingOn: waitingOn}); err != nil {
			return nil, false, errs.Wrap(err, "unable to update check suite")
		}
	}

	runComplete := req.GetComplete()
	if runComplete != nil {
		var azpCompletedAt time.Time

		if runComplete.CompletedAt != nil {
			azpCompletedAt = runComplete.CompletedAt.AsTime()
			delay := time.Since(azpCompletedAt)
			withinThreshold := delay < thresholds.RunCompletionDelay
			s.stats.LegacyTiming(ctx, "run_completion_delay", statter.Tags{"within_threshold": strconv.FormatBool(withinThreshold), "workflow_healed": "false"}, delay)
		} else {
			s.log.Report(ctx, errs.New("completed workflow run missing completed_at time"))
			azpCompletedAt = time.Now()
		}

		conclusion := mapBuildConclusion(runComplete.GetConclusion())
		if err := s.buildRepo.Complete(ctx, time.Now(), azpCompletedAt, dbData.WorkflowBuildDatabaseID, conclusion); err != nil {
			return nil, false, errs.Wrapf(err, "Could not mark build as completed (conclusion %s)", conclusion)
		}
	}

	return dbData, false, nil
}

// Returns checkRunID or checkSuiteID from database
// Actions service sends both RunExternalId and JobExternalId as part of postback
// In case of waiting on normal job, JobExternalId always exists in database
// In case of waiting on job uses called workflow, JobExternalId won't exists in database, so we fallback to RunExternalId
// In case of waiting on run, we check for RunExternalId
func (s *service) getWaitingOn(ctx context.Context, concurrency *Concurrency, workflowDatabaseID int64) (*WaitingOn, error) {
	waitingOn := &WaitingOn{
		CheckSuiteID: types.NilGlobalID,
		CheckRunID:   types.NilGlobalID,
	}

	// query db to translate WaitingOnResource data from Actions service IDs to dotcom IDs
	if concurrency == nil || concurrency.WaitingOnResource == nil {
		return waitingOn, nil
	}

	err := s.buildRepo.SetWasDelayed(ctx, workflowDatabaseID)
	if err != nil {
		return waitingOn, err
	}

	externalBuildID := concurrency.WaitingOnResource.RunExternalId
	externalJobID := concurrency.WaitingOnResource.JobExternalId

	if externalJobID != "" {
		waitingOnCheckRunID, err := s.getWaitingOnExternalJobID(ctx, externalJobID)
		if waitingOnCheckRunID != types.NilGlobalID {
			waitingOn.CheckRunID = waitingOnCheckRunID
			return waitingOn, err
		}
	}

	if externalBuildID != "" {
		waitingOnCheckSuiteID, err := s.getWaitingOnExternalBuildID(ctx, externalBuildID)
		if waitingOnCheckSuiteID != types.NilGlobalID {
			waitingOn.CheckSuiteID = waitingOnCheckSuiteID
			return waitingOn, err
		}
	}
	return waitingOn, nil
}

func (s *service) getWaitingOnExternalJobID(ctx context.Context, externalJobID string) (types.GlobalID, error) {
	// validate JobExternalId is comma delimited pair of UUIDs
	split := strings.Split(externalJobID, ",")
	if len(split) != 2 {
		return types.NilGlobalID, errs.Errorf("JobExternalId %q expected to in format <planid>,<jobid>", externalJobID)
	}
	for _, value := range split {
		_, err := uuid.Parse(value)
		if err != nil {
			return types.NilGlobalID, errs.Errorf("unable to parse uuid from JobExternalId %q", externalJobID)
		}
	}
	waitingForCheckRunResource, ok, err := s.buildRepo.GetWaitingOnResourceCheckRunID(ctx, externalJobID)
	if err != nil {
		return types.NilGlobalID, errs.New("error retrieving CheckRunResource")
	}
	if !ok {
		return types.NilGlobalID, nil
	}

	waitingOnCheckRunID := waitingForCheckRunResource.WorkflowJobCheckRunID
	return waitingOnCheckRunID, nil
}

func (s *service) getWaitingOnExternalBuildID(ctx context.Context, externalBuildID string) (types.GlobalID, error) {
	waitingForCheckSuiteResource, ok, err := s.buildRepo.GetWaitingOnResourceCheckSuiteID(ctx, externalBuildID)
	if err != nil {
		return types.NilGlobalID, errs.New("error retrieving CheckRunResource")
	}
	if !ok {
		return types.NilGlobalID, nil
	}

	waitingOnCheckSuiteID := waitingForCheckSuiteResource.WorkflowBuildCheckSuiteID
	return waitingOnCheckSuiteID, nil
}

func mapBuildConclusion(conclusion RunConclusion) build.WorkflowState {
	// Conclusion is a protobuf enum so this must be all the cases
	switch conclusion {
	case RunConclusion_SUCCEEDED:
		return build.WorkflowStateSucceeded
	case RunConclusion_CANCELED:
		return build.WorkflowStateCanceled
	case RunConclusion_SKIPPED:
		return build.WorkflowStateSkipped
	default: // eg. RunConclusion_FAILED, RunConclusion_NOT_PROVIDED
		return build.WorkflowStateFailed
	}
}

func (s *service) emitWorkflowExecution(queuedAt *timestamp.Timestamp, completedAt *timestamp.Timestamp, dbData *deployer.DataForStatusPostback, rmd metadata.WorkflowMetadata, conclusion entities.CheckSuiteConclusion) {
	// New timestamp fields
	queuedTime := timestamppb.New(dbData.GetQueuedAt())
	startedTime := timestamppb.New(dbData.GetStartedAt())

	s.hydro.EmitWorkflowExecution(&hydroV0.WorkflowExecution{
		WorkflowStartTime:          queuedAt,
		WorkflowEndTime:            completedAt,
		ExternalProvider:           hydroV0.WorkflowExecution_AZP,
		ExternalProviderReference:  dbData.ExternalBuildID,
		InvokingUserId:             uint64(rmd.InvokingUser.GetID()),
		WorkflowRepositoryOwnerId:  uint64(rmd.RepositoryOwner.GetID()),
		WorkflowRepositorySha:      dbData.CheckSuiteState.EventSHA.String(),
		WorkflowFilePath:           dbData.CheckSuiteState.WorkflowFilePath,
		WorkflowBuildId:            uint64(dbData.WorkflowBuildDatabaseID),
		WorkflowRepositoryGlobalId: dbData.WorkflowMetadata.Repository.GlobalRelayID,
		WorkflowRepositoryId:       uint64(dbData.WorkflowMetadata.Repository.ID),
		WorkflowRunId:              uint64(dbData.CheckSuiteState.WorkflowRunID),
		CheckSuiteConclusion:       conclusion,
		CheckSuiteGlobalId:         dbData.CheckSuiteState.CheckSuiteIDPair.GlobalID.String(),
		QueuedAt:                   queuedTime,
		StartedAt:                  startedTime,
		CompletedAt:                completedAt,
		WorkflowName:               []byte(dbData.CheckSuiteState.FlowIdentifier),
		Attempt:                    *dbData.Attempt,
	})
}

func mapExecutionConclusion(update *RunStatusRequest) entities.CheckSuiteConclusion {
	completed := update.GetComplete()
	if completed == nil {
		return entities.CheckSuiteConclusion_UNKNOWN
	}

	conclusion := completed.GetConclusion()
	switch conclusion {
	case RunConclusion_SUCCEEDED:
		return entities.CheckSuiteConclusion_SUCCESS
	case RunConclusion_FAILED:
		return entities.CheckSuiteConclusion_FAILURE
	case RunConclusion_CANCELED:
		return entities.CheckSuiteConclusion_CANCELLED
	case RunConclusion_SKIPPED:
		return entities.CheckSuiteConclusion_SKIPPED
	default:
		return entities.CheckSuiteConclusion_UNKNOWN
	}
}

// handleEmissionError logs and counts an errored hydro event and metadata about
// the event that we missed.
func (s *service) handleEmissionError(ctx context.Context, err error, eventType string, fields ...kvp.Field) {
	if evtErr, ok := err.(*EventableError); ok {
		if evtErr.shouldEmitEvent {
			fields = append(fields, kvp.String("gh.launch.event.type", eventType), kvp.Err(err))
			s.log.Error(ctx, "errored before emitting event", fields...)
			s.hydro.CountErroredEvent(eventType)
		}
	}
}

func (s *service) checkRepoDeletedState(ctx context.Context, dbData *deployer.DataForStatusPostback, workflowID string) bool {
	azpEntity, err := s.azpResourcesRepo.TryGet(ctx, dbData.CheckSuiteState.RepositoryID)
	if err != nil {
		if _, ok := errs.Cause(err).(*deployer.GetAzpResourcesError); ok {
			return true // repo is deleted if azp_resources is not found
		}

		s.log.Report(ctx, errs.Wrap(err, "Error checking if repository is deleted"),
			kvp.String("gh.repo.global_id", dbData.CheckSuiteState.RepositoryID.String()),
			kvp.String("gh.launch.workflow.identifier", workflowID),
		)
	} else if azpEntity == nil || (azpEntity.CreatedAt != nil && azpEntity.CreatedAt.After(dbData.CreatedAt)) {
		return true // azp_resources is a restored repository.
	}
	return false
}

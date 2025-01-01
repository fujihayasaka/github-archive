package results

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-twirp/client/auth"
	twirprequestid "github.com/github/go-twirp/client/requestid"
	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/pkg/results/entities/events"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/graphqlid"
	"github.com/github/launch/utils/requestid"

	resultspb "github.com/github/actions-proto/gen/go/results/api/v1"

	"github.com/github/launch/clients/aqueduct"
)

const (
	actionsResultsEventsQueue = "actions-results-events"
	actionsResultsEventHeader = "actions-results-event"
	workflowRunUpdateEvent    = "workflow-run-update"
	resultsAqueductApp        = "actions-results-production"
	defaultWorkerID           = 0

	// Results expects "request_id" instead of the standard X-GitHub-Request-ID header
	// https://github.com/search?q=repo:github/actions-results%20Headers%5B%22request_id%22%5D&type=code
	RequestIDHeader = "request_id"
)

// Config denotes configuration required for a results client
type Config struct {
	AqueductURL           string
	AqueductAPIKey        string
	AqueductAPIKeyVersion int
	CoreURL               string
	CoreHMACSecret        string
}

// RunStartDelaySLOMetadata denotes metadata used by the Results service to calculate SLOs
type RunStartDelaySLOMetadata struct {
	EventCreatedAt            time.Time
	EventName                 string
	CustomerLabel             string
	DynamicWorkflowIntegrator string
	IgnoreFromRunStartDelay   bool
	IsRunFromLab              bool
}

type Client interface {
	CreateWorkflowRun(ctx context.Context, workflowRunBackendID types.WorkflowExecutionID, checkSuiteState *types.CheckSuiteState, logRetentionDays int64, sloMetadata *RunStartDelaySLOMetadata, previousAttemptWorkflowRunBackendID string) error
	GetWorkflowRunState(ctx context.Context, workflowRunBackendID types.WorkflowExecutionID) (*resultspb.GetWorkflowRunStateResponse, error)
	GetWorkflowOrchestrationContexts(ctx context.Context, workflowRunBackendID types.WorkflowExecutionID) ([]string, error)
	UpdateWorkflowRun(ctx context.Context, update *events.WorkflowRunUpdate) error
}

type WorkflowUpdateService interface {
	resultspb.WorkflowUpdateService
}

type client struct {
	aqueductClient        aqueduct.Client
	workflowUpdateService resultspb.WorkflowUpdateService
	aqueductApp           string
	sendOptions           []aqueduct.SendOption
	obs                   *observability.Observability
}

func NewClient(
	cfg Config,
	aqueductClientFactory aqueduct.Factory,
	aqueductBreaker *circuit.Breaker,
	httpClient *http.Client,
	twirpBreaker *circuit.Breaker,
	obs *observability.Observability,
) (*client, error) {
	clientOptions := &aqueduct.ClientOptions{
		App:           resultsAqueductApp,
		URL:           cfg.AqueductURL,
		WorkerID:      defaultWorkerID,
		APIKey:        cfg.AqueductAPIKey,
		APIKeyVersion: cfg.AqueductAPIKeyVersion,
	}

	aq, err := aqueductClientFactory.NewClient(obs.Statter, aqueductBreaker, clientOptions)
	if err != nil {
		return nil, errors.Wrap(err, "error creating Aqueduct client for results")
	}

	retryHTTPClient := ahttp.NewRetryClient(twirpBreaker, obs.Statter, httpClient, "resultstwirp")
	signingHTTPClient, err := auth.NewRequestHMACSigner(cfg.CoreHMACSecret, retryHTTPClient)
	if err != nil {
		return nil, errors.Wrap(err, "error creating HMAC signer for results")
	}
	workflowUpdateService := resultspb.NewWorkflowUpdateServiceProtobufClient(cfg.CoreURL, twirprequestid.NewForwarder(signingHTTPClient))

	return &client{
		aqueductClient:        aq,
		aqueductApp:           resultsAqueductApp,
		workflowUpdateService: workflowUpdateService,
		sendOptions: []aqueduct.SendOption{
			aqueduct.WithJobRedeliveryTimeoutSeconds(120), // default is 600 (10 minutes)
			aqueduct.WithJobMaxRedeliveryAttempts(4),      // default is 2 redeliveries (first delivery doesn't count)
		},
		obs: obs,
	}, nil
}

// globalIDToRepositoryID converts a global ID to an int64 repository ID
func globalIDToDatabaseID(globalID types.GlobalID, targetType string) (int64, error) {
	t, id, err := graphqlid.DecodeTypeIntID(globalID.String())
	if err != nil {
		return 0, errors.Wrap(err, "failed to decode GlobalID")
	}

	if t != targetType {
		return 0, fmt.Errorf("unexpected global id type %s, expected %s", t, targetType)
	}

	return id, nil
}

// CreateWorkflowRun calls Results Core to create workflow run synchronously
func (c *client) CreateWorkflowRun(ctx context.Context, workflowRunBackendID types.WorkflowExecutionID, checkSuiteState *types.CheckSuiteState, logRetentionDays int64, sloMetadata *RunStartDelaySLOMetadata, previousAttemptWorkflowRunBackendID string) error {
	ctx = requestid.ForwardRequestIDToTwirp(ctx)
	if checkSuiteState == nil {
		return errors.New("check suite state or check suite id pair is nil")
	}

	repositoryID, err := globalIDToDatabaseID(checkSuiteState.RepositoryID, types.GlobalIDRepositoryType)
	if err != nil {
		return errors.Wrap(err, "failed to convert global id to repository id")
	}

	checkSuiteDatabaseID := checkSuiteState.CheckSuiteIDPair.DatabaseID
	if checkSuiteDatabaseID == 0 { // the database ID is not set on re-runs, so we need to convert the global ID
		checkSuiteDatabaseID, err = globalIDToDatabaseID(checkSuiteState.CheckSuiteIDPair.GlobalID, types.GlobalIDCheckSuiteType)
		if err != nil {
			return errors.Wrap(err, "failed to convert global id to check suite id")
		}
	}

	workflowRunCreateRequest := &resultspb.WorkflowRunCreateRequest{
		WorkflowRunBackendId:                workflowRunBackendID.String(),
		RepositoryId:                        repositoryID,
		CheckSuiteId:                        checkSuiteDatabaseID,
		EventName:                           sloMetadata.EventName,
		CustomerLabel:                       sloMetadata.CustomerLabel,
		IgnoreFromRunStartDelay:             sloMetadata.IgnoreFromRunStartDelay,
		DynamicWorkflowIntegrator:           sloMetadata.DynamicWorkflowIntegrator,
		PreviousAttemptWorkflowRunBackendId: previousAttemptWorkflowRunBackendID,
		IsRunFromLab:                        sloMetadata.IsRunFromLab,
	}

	if logRetentionDays > 0 {
		workflowRunCreateRequest.LogRetentionDays = logRetentionDays
	}

	if !sloMetadata.EventCreatedAt.IsZero() {
		workflowRunCreateRequest.EventCreatedAt = timestamppb.New(sloMetadata.EventCreatedAt)
	}

	c.obs.Debug(
		ctx,
		"creating workflow run in results service",
		kvp.String("gh.launch.workflow_run.backend_id", workflowRunCreateRequest.GetWorkflowRunBackendId()),
		kvp.Int64("gh.repo.id", workflowRunCreateRequest.GetRepositoryId()),
		kvp.Int64("gh.check_suite.id", workflowRunCreateRequest.GetCheckSuiteId()),
		kvp.Int64("gh.launch.log_retention_days", workflowRunCreateRequest.GetLogRetentionDays()),
		kvp.String("gh.launch.event.name", workflowRunCreateRequest.GetEventName()),
		kvp.Time("gh.launch.event.created_at", workflowRunCreateRequest.GetEventCreatedAt().AsTime()),
		kvp.String("gh.launch.customer_label", workflowRunCreateRequest.GetCustomerLabel()),
		kvp.String("gh.launch.dynamic_workflow_integrator", workflowRunCreateRequest.GetDynamicWorkflowIntegrator()),
		kvp.Bool("gh.launch.ignore_from_start_delay", workflowRunCreateRequest.GetIgnoreFromRunStartDelay()),
		kvp.String("gh.launch.previous_attempt_workflow_run_backend_id", workflowRunCreateRequest.GetPreviousAttemptWorkflowRunBackendId()),
	)

	resp, err := c.workflowUpdateService.WorkflowRunCreate(ctx, workflowRunCreateRequest)
	if err != nil {
		return err
	}
	if !resp.Ok {
		return twirp.InternalError("failed to create workflow run from results")
	}

	c.obs.Debug(
		ctx,
		"results create workflow run successful",
		kvp.String("gh.launch.workflow_run.backend_id", workflowRunBackendID.String()),
		kvp.Int64("gh.repo.id", repositoryID),
		kvp.Int64("gh.check_suite.id", checkSuiteDatabaseID),
	)

	return nil
}

// GetWorkflowRunState calls Results Core to get the workflow run state (completed_at, status, etc)
func (c *client) GetWorkflowRunState(ctx context.Context, workflowRunBackendID types.WorkflowExecutionID) (*resultspb.GetWorkflowRunStateResponse, error) {
	workflowRunStateRequest := &resultspb.GetWorkflowRunStateRequest{
		WorkflowRunBackendId: workflowRunBackendID.String(),
	}

	resp, err := c.workflowUpdateService.GetWorkflowRunState(ctx, workflowRunStateRequest)
	if err != nil {
		return nil, err
	}

	return resp, nil
}

// GetWorkflowOrchestrationContexts calls Results Core to get workflow orchestration contexts synchronously
func (c *client) GetWorkflowOrchestrationContexts(ctx context.Context, workflowRunBackendID types.WorkflowExecutionID) ([]string, error) {
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	workflowOrcContextsRequest := &resultspb.GetWorkflowOrchestrationContextsRequest{
		WorkflowRunBackendId: workflowRunBackendID.String(),
	}

	c.obs.Debug(
		ctx,
		"getting workflow orchestration contexts from results service",
		kvp.String("gh.launch.workflow_run.backend_id", workflowOrcContextsRequest.GetWorkflowRunBackendId()),
	)

	resp, err := c.workflowUpdateService.GetWorkflowOrchestrationContexts(ctx, workflowOrcContextsRequest)
	if err != nil {
		return nil, err
	}

	c.obs.Debug(
		ctx,
		"got orchestration contexts from results successfully",
		kvp.String("gh.launch.workflow_run.backend_id", workflowRunBackendID.String()),
		kvp.Int("gh.launch.context_length", len(resp.OrchestrationContexts)),
	)

	return resp.OrchestrationContexts, nil
}

// UpdateWorkflowRun asynchronously updates a workflow run in results which will also update the monolith.
func (c *client) UpdateWorkflowRun(ctx context.Context, update *events.WorkflowRunUpdate) error {
	payload, err := proto.Marshal(update)
	if err != nil {
		return err
	}

	jobID, err := c.aqueductClient.Send(ctx, aqueduct.Job{
		App:     c.aqueductApp,
		Queue:   actionsResultsEventsQueue,
		Payload: payload,
		Headers: map[string]string{
			actionsResultsEventHeader:    workflowRunUpdateEvent,
			RequestIDHeader:              ctxstash.From(ctx).Correlations().GitHub.RequestID,
			ctxstash.VSSCorrelationIDKey: ctxstash.From(ctx).Correlations().VSS.CorrelationID,
		},
	}, c.sendOptions...)
	if err != nil {
		return err
	}

	c.obs.Debug(ctx, "results events message sent to aqueduct",
		kvp.String("gh.aqueduct.app", c.aqueductApp),
		kvp.String("gh.aqueduct.queue.name", actionsResultsEventsQueue),
		kvp.String("gh.aqueduct.job.id", jobID),
	)
	return nil
}

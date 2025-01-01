package status

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/github/launch/observability/ctxstash"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	proto "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"

	entities "github.com/github/launch/hydro/schemas/github/v1/entities"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/pkg/results/entities/usage"
)

// resultsUsageClient handles usage updates that are sent to the results service
type resultsUsageClient struct {
	aqueductClient aqueduct.Client
	resultsApp     string
	log            logs
}

var _ usageClient = (*resultsUsageClient)(nil)

const (
	actionsUsageEventsQueue = "actions-usage-events"
	usageEvent              = "usage-event"
)

var (
	usageAqueductOptions = []aqueduct.SendOption{
		aqueduct.WithJobRedeliveryTimeoutSeconds(120), // default is 600 (10 minutes)
		aqueduct.WithJobMaxRedeliveryAttempts(4),      // default is 2 redeliveries (first delivery doesn't count)
	}
)

func newResultsUsageClient(aqueductClient aqueduct.Client, log logs) *resultsUsageClient {
	return &resultsUsageClient{
		aqueductClient: aqueductClient,
		resultsApp:     "actions-results-production",
		log:            log,
	}
}

func (client *resultsUsageClient) EmitUsage(ctx context.Context, dbData *deployer.DataForStatusPostback, jobID int64, checkRunID int64, update *JobStatusRequest, complete *JobComplete, billingChecked bool) error {
	workflowMetadata := dbData.WorkflowMetadata
	checkSuiteState := dbData.CheckSuiteState

	var customerID uint64
	if workflowMetadata.CustomerID != nil {
		customerID = uint64(*workflowMetadata.CustomerID)
	}

	// First we must build the JobExecution event using the data passed in
	jobExecution := &usage.JobExecution{
		InvokingUserId:               uint64(workflowMetadata.InvokingUser.GetID()),
		InvokingEventType:            dbData.Event,
		WorkflowRepositoryId:         uint64(workflowMetadata.Repository.ID),
		WorkflowRepositoryGlobalId:   workflowMetadata.Repository.GlobalRelayID,
		WorkflowRepositoryVisibility: visibilityCast(workflowMetadata.Repository.Visibility),
		WorkflowRepositoryOwnerId:    uint64(workflowMetadata.RepositoryOwner.GetID()),
		WorkflowRepositorySha:        checkSuiteState.EventSHA.String(),
		WorkflowFilePath:             checkSuiteState.WorkflowFilePath,
		WorkflowName:                 checkSuiteState.FlowIdentifier,
		WorkflowBuildId:              uint64(dbData.WorkflowBuildDatabaseID),
		CheckSuiteGlobalId:           string(checkSuiteState.CheckSuiteIDPair.GlobalID),
		JobId:                        fmt.Sprintf("%d", jobID),
		JobRuntime:                   convertRuntime(update.GetRuntime()),
		JobRuntimeVersion:            update.RuntimeVersion,
		CheckRunId:                   uint64(checkRunID),
		JobUserIdentifier:            update.JobKey,
		StartTime:                    complete.StartedAt,
		EndTime:                      complete.CompletedAt,
		QueuedAt:                     update.QueuedAt,
		JobExecutionBillableMs:       uint64(update.DurationMs),
		SelfHosted:                   update.SelfHosted,
		BillingChecked:               billingChecked,
		LogUrl:                       complete.Log.GetUrl(),
		RunnerProperties:             update.RunnerProperties,
		RunnerType:                   convertRunnerType(update.GetRunnerType()),
		BillableOwnerId:              update.BillableOwnerId,
		CheckRunConclusion:           resultCast(complete.Result),
		ExternalJobId:                update.ExternalId,
		ProductSku:                   update.ProductSku,
		JobName:                      update.DisplayName,
		WorkflowRunId:                uint64(checkSuiteState.WorkflowRunID),
		WorkflowRunAttempt:           *dbData.Attempt,
		CustomerId:                   customerID,
		LastCompletedStepAt:          getLatestStepCompletedAt(update),
	}

	payload, err := proto.Marshal(jobExecution)

	if err != nil {
		return errors.Wrap(err, "Oopsies! Failed to marshal job_execution")
	}

	jobEventID, err := client.aqueductClient.Send(ctx, aqueduct.Job{
		App:     client.resultsApp,
		Queue:   actionsUsageEventsQueue,
		Payload: payload,
		Headers: map[string]string{
			actionsResultsEventHeader:    usageEvent,
			results.RequestIDHeader:      ctxstash.From(ctx).Correlations().GitHub.RequestID,
			ctxstash.VSSCorrelationIDKey: ctxstash.From(ctx).Correlations().VSS.CorrelationID,
		},
	}, usageAqueductOptions...)

	if err != nil {
		client.log.Debug(ctx, "results events message failed to send to aqueduct",
			kvp.String("gh.aqueduct.app", client.resultsApp),
			kvp.String("gh.aqueduct.queue.name", actionsUsageEventsQueue))

		return err
	}

	client.log.Debug(ctx, "results events message sent to aqueduct",
		kvp.String("gh.aqueduct.app", client.resultsApp),
		kvp.String("gh.aqueduct.queue.name", actionsUsageEventsQueue),
		kvp.String("gh.aqueduct.job.id", jobEventID))

	return nil
}

func getLatestStepCompletedAt(update *JobStatusRequest) *timestamppb.Timestamp {
	var (
		latestStepCompletedAt *time.Time
	)

	for _, step := range update.Steps {
		if step.GetComplete() == nil || step.GetComplete().GetCompletedAt() == nil {
			continue
		}

		stepCompletedAt := step.GetComplete().CompletedAt.AsTime()
		if latestStepCompletedAt == nil || latestStepCompletedAt.Before(stepCompletedAt) {
			latestStepCompletedAt = &stepCompletedAt
		}
	}

	if latestStepCompletedAt == nil {
		return nil
	}

	return timestamppb.New(*latestStepCompletedAt)
}

func resultCast(result Result) usage.JobExecution_Conclusion {
	switch result {
	case Result_RESULT_SUCCEEDED:
		return usage.JobExecution_RESULT_SUCCESS
	case Result_RESULT_CANCELED:
		return usage.JobExecution_RESULT_CANCELLED
	case Result_RESULT_FAILED:
		return usage.JobExecution_RESULT_FAILURE
	case Result_RESULT_PARTIALLY_SUCCEEDED:
		return usage.JobExecution_RESULT_PARTIALLY_SUCCEEDED
	case Result_RESULT_SKIPPED:
		return usage.JobExecution_RESULT_SKIPPED
	default:
		return usage.JobExecution_RESULT_UNKNOWN
	}
}

// Used to convert between Repository.Visibility and JobExecution.Visibility
func visibilityCast(visibility entities.Repository_Visibility) usage.JobExecution_Visibility {
	switch visibility {
	case entities.Repository_PUBLIC:
		return usage.JobExecution_PUBLIC
	case entities.Repository_PRIVATE:
		return usage.JobExecution_PRIVATE
	case entities.Repository_INTERNAL:
		return usage.JobExecution_INTERNAL
	default:
		return usage.JobExecution_VISIBILITY_UNKNOWN
	}
}

// Converts runner type from job status request into a format suitable for
// JobExecution
func convertRunnerType(runnerType string) usage.JobExecution_RunnerType {
	switch strings.ToLower(runnerType) {
	case "self_hosted":
		return usage.JobExecution_RUNNER_TYPE_SELF_HOSTED
	case "hosted":
		return usage.JobExecution_RUNNER_TYPE_HOSTED
	case "custom":
		return usage.JobExecution_RUNNER_TYPE_CUSTOM
	default:
		return usage.JobExecution_RUNNER_TYPE_UNKNOWN
	}
}

// Converts runtime from job status request into a format suitable for
// JobExecution
func convertRuntime(runtime string) usage.JobExecution_Runtime {
	switch strings.ToLower(runtime) {
	case "macos":
		return usage.JobExecution_MACOS
	case "windows":
		return usage.JobExecution_WINDOWS
	case "ubuntu":
		return usage.JobExecution_UBUNTU
	default:
		return usage.JobExecution_RUNTIME_UNKNOWN
	}
}

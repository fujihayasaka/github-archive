package status

import (
	"context"
	"fmt"

	"github.com/github/launch/db/stores/deployer"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
)

type hydroUsageClient struct {
	hydro Hydro
	log   logs
}

func newHydroUsageClient(hydro Hydro, log logs) *hydroUsageClient {
	return &hydroUsageClient{
		hydro: hydro,
		log:   log,
	}
}

func (client *hydroUsageClient) EmitUsage(_ context.Context, dbData *deployer.DataForStatusPostback, jobID int64, checkRunID int64, update *JobStatusRequest, complete *JobComplete, billingChecked bool) error {
	workflowMetadata := dbData.WorkflowMetadata
	checkSuiteState := dbData.CheckSuiteState

	client.hydro.EmitJobExecution(&hydroV0.JobExecution{
		InvokingUserId:               uint64(workflowMetadata.InvokingUser.GetID()),
		InvokingEventType:            dbData.Event,
		WorkflowRepositoryId:         uint64(workflowMetadata.Repository.ID),
		WorkflowRepositoryGlobalId:   workflowMetadata.Repository.GlobalRelayID,
		WorkflowRepositoryVisibility: castVisibility(workflowMetadata.Repository.Visibility),
		WorkflowRepositoryOwnerId:    uint64(workflowMetadata.RepositoryOwner.GetID()),
		WorkflowRepositorySha:        checkSuiteState.EventSHA.String(),
		WorkflowFilePath:             checkSuiteState.WorkflowFilePath,
		WorkflowName:                 checkSuiteState.FlowIdentifier,
		WorkflowBuildId:              uint64(dbData.WorkflowBuildDatabaseID),
		CheckSuiteId:                 uint64(checkSuiteState.CheckSuiteIDPair.DatabaseID),
		JobId:                        fmt.Sprintf("%d", jobID),
		JobRuntime:                   castRuntime(update.GetRuntime()),
		JobRuntimeVersion:            update.RuntimeVersion,
		CheckRunId:                   uint64(checkRunID),
		JobUserIdentifier:            update.JobKey,
		StartTime:                    complete.StartedAt,
		EndTime:                      complete.CompletedAt,
		JobExecutionBillableMs:       uint64(update.DurationMs),
		BillingChecked:               billingChecked,
		LogUrl:                       complete.Log.GetUrl(),
		RunnerProperties:             update.RunnerProperties,
		RunnerType:                   castRunnerType(update.GetRunnerType()),
	})

	return nil
}

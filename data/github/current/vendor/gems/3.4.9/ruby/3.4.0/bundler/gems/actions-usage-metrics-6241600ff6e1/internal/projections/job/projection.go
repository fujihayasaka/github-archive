package job

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type JobUsageItem struct {
	// Grouping
	RepositoryOwnerId string `json:"repositoryOwnerId" kusto:"repositoryOwnerId"`
	RepositoryId      int64  `json:"repositoryId" kusto:"repositoryId"`
	WorkflowFilePath  string `json:"workflowFilePath" kusto:"workflowFilePath"`
	JobUserIdentifier string `json:"jobUserIdentifier" kusto:"jobUserIdentifier"`
	JobName           string `json:"jobName" kusto:"jobName"` // We currently consider a renamed display name to be a different job
	RunnerType        string `json:"runnerType" kusto:"runnerType"`
	RunnerRuntime     string `json:"runnerRuntime" kusto:"runnerRuntime"`
	RunnerLabels      string `json:"runnerRequestedLabel" kusto:"runnerRequestedLabel"`

	// Workflow name (for filtering)
	WorkflowFileName string `json:"workflowFileName" kusto:"workflowFileName"`

	// Aggregations
	TotalMinutes        int64 `json:"totalMinutes" kusto:"totalMinutes"`
	TotalFailureMinutes int64 `json:"totalFailureMinutes" kusto:"totalFailureMinutes"`
	JobExecutions       int64 `json:"jobExecutions" kusto:"jobExecutions"`

	// Performance
	AverageRunTime   int64   `json:"averageRunTime" kusto:"averageRunTime"`
	AverageQueueTime int64   `json:"averageQueueTime" kusto:"averageQueueTime"`
	FailureRate      float64 `json:"failureRate" kusto:"failureRate"`
}

type jobProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func JobProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return jobProjection{version, scope}
}

var _ common.Projection[JobUsageItem] = &jobProjection{}

const ProjectionName = common.ProjectionName_ActionsJobUsage

func (jobProjection) Name() common.ProjectionName   { return ProjectionName }
func (p jobProjection) Version() versioning.Version { return p.version }

func (p jobProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.GetKustoTableOrView(common.JobsTableType, aggInterval, p.version, p.scope, true)
}

func (p jobProjection) KustoQuery() *kql.Builder {
	return kql.New(`
		| extend workflowFilePath=base64_decode_tostring(workflowFilePath)
		| summarize
			totalMinutes=sum(totalMinutes),
			jobExecutions=sum(jobExecutions),
			totalRunTime=sum(totalRunTime),
			totalQueueTime=sum(totalQueueTime),
			failures=sum(failures),
			totalFailureMinutes=sum(totalFailureMinutes),
			runnerLabels=split(take_any(runnerRequestedLabel), ",")
			by
			repositoryOwnerId,
			repositoryId,
			workflowFilePath,
			workflowFileName=tostring(split(workflowFilePath, "/")[-1]),
			jobUserIdentifier,
			jobName=base64_decode_tostring(jobName),
			runnerType,
			runnerRequestedLabel
		| extend
			averageRunTime=totalRunTime/jobExecutions,
			averageQueueTime=totalQueueTime/jobExecutions,
			failureRate=(toreal(failures) * 100)/toreal(jobExecutions)
	`)
}

func (p jobProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

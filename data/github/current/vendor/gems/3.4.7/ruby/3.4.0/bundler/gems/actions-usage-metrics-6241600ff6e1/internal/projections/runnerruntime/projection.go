package runnerruntime

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type RunnerRuntimeUsageItem struct {
	// Grouping
	RunnerRuntime string `json:"runnerRuntime" kusto:"runnerRuntime"`

	// Aggregations
	TotalMinutes        int64 `json:"totalMinutes" kusto:"totalMinutes"`
	TotalFailureMinutes int64 `json:"totalFailureMinutes" kusto:"totalFailureMinutes"`
	JobExecutions       int64 `json:"jobExecutions" kusto:"jobExecutions"`
	WorkflowExecutions  int64 `kusto:"workflowExecutions"`
	Workflows           int64 `kusto:"workflows"`

	// Performance
	AverageRunTime   int64   `json:"averageRunTime" kusto:"averageRunTime"`
	AverageQueueTime int64   `json:"averageQueueTime" kusto:"averageQueueTime"`
	FailureRate      float64 `json:"failureRate" kusto:"failureRate"`
}

type runnerRuntimeProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func RunnerRuntimeProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return runnerRuntimeProjection{version, scope}
}

var _ common.Projection[RunnerRuntimeUsageItem] = &runnerRuntimeProjection{}

const ProjectionName = common.ProjectionName_ActionsRunnerRuntimeUsage

func (runnerRuntimeProjection) Name() common.ProjectionName   { return ProjectionName }
func (p runnerRuntimeProjection) Version() versioning.Version { return p.version }

func (p runnerRuntimeProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.GetKustoTableOrView(common.RunnerRuntimesTableType, aggInterval, p.version, p.scope, true)
}

func (p runnerRuntimeProjection) KustoQuery() *kql.Builder {
	return kql.New(`
		| summarize
			totalMinutes=sum(totalMinutes),
			jobExecutions=sum(jobExecutions),
			workflowExecutions=dcount_hll(hll_merge(workflowRunHll)),
			workflows=dcount_hll(hll_merge(workflowFilePathHll)),
			totalRunTime=sum(totalRunTime),
			totalQueueTime=sum(totalQueueTime),
			failures=sum(failures),
			totalFailureMinutes=sum(totalFailureMinutes)
			by
			runnerRuntime
		| extend
			averageRunTime=totalRunTime/jobExecutions,
			averageQueueTime=totalQueueTime/jobExecutions,
			failureRate=(toreal(failures) * 100)/toreal(jobExecutions)
	`)
}

func (p runnerRuntimeProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

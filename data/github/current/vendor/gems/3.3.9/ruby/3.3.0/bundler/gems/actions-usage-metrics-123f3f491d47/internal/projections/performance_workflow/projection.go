package performance_workflow

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type WorkflowPerformanceItem struct {
	// Grouping
	RepositoryId        int64   `json:"repositoryId" kusto:"repositoryId"`
	WorkflowFilePath    string  `json:"workflowFilePath" kusto:"workflowFilePath"`
	WorkflowFileName    string  `json:"workflowFileName" kusto:"workflowFileName"`
	WorkflowExecutions  int64   `json:"workflowExecutions" kusto:"workflowExecutions"`
	Jobs                int64   `json:"jobs" kusto:"jobs"`
	AverageRunTime      int64   `json:"averageRunTime" kusto:"averageRunTime"`
	FailureRate         float64 `json:"failureRate" kusto:"failureRate"`
	TotalFailureMinutes int64   `json:"totalFailureMinutes" kusto:"totalFailureMinutes"`
}

type workflowPerformanceProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func WorkflowPerformanceProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return workflowPerformanceProjection{version, scope}
}

var _ common.Projection[WorkflowPerformanceItem] = &workflowPerformanceProjection{}

const ProjectionName = common.ProjectionName_ActionsWorkflowUsage

func (workflowPerformanceProjection) Name() common.ProjectionName   { return ProjectionName }
func (p workflowPerformanceProjection) Version() versioning.Version { return p.version }

func (p workflowPerformanceProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	// performance workflows MV is not aggregated by day/month, but by aggregating all job runs into workflow runs. Because of this the daily view
	// is not a true daily view, but rather a workflow view of the job data, and there is no monthly aggregation so we need to hardcode the daily view
	// see https://github.com/github/actions-fusion/issues/1814#issuecomment-2285139691 for more info
	return common.GetKustoTableOrViewForPerformance(common.WorkflowsTableType, common.ProjectionAggregationIntervalDaily, p.version, p.scope, true)
}

func (p workflowPerformanceProjection) KustoQuery() *kql.Builder {
	return kql.New(`
		| extend runTime = tolong((lastJobCompleted - timestamp)/time(1ms))
		| summarize hint.strategy=shuffle // aggregate all workflows runs over given day
			totalMinutes=sum(totalMinutes),
			totalFailureMinutes=sum(totalFailureMinutes),
			jobs=dcount_hll(hll_merge(jobUserIdentifierHll)),
			workflowExecutions=count(),
			totalRunTime=sum(runTime),
			failures=countif(jobFailureCount > 0)
			by
			repositoryOwnerId=repositoryOwnerId,
			workflowFilePath=workflowFilePath, // base64 encoded
			repositoryId=repositoryId
		| extend workflowFilePath=base64_decode_tostring(workflowFilePath)
		| extend
			workflowFileName=tostring(split(workflowFilePath, "/")[-1]),
			averageRunTime=totalRunTime/workflowExecutions,
			failureRate=(toreal(failures) * 100)/toreal(workflowExecutions)
	`)
}

func (p workflowPerformanceProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

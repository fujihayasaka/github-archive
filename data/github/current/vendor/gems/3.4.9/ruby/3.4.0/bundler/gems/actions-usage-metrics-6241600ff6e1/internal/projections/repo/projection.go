package repo

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type RepoUsageItem struct {
	// Grouping
	RepositoryOwnerId string `json:"repositoryOwnerId" kusto:"repositoryOwnerId"`
	RepositoryId      int64  `json:"repositoryId" kusto:"repositoryId"`

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

type repoProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func RepoProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return repoProjection{version, scope}
}

var _ common.Projection[RepoUsageItem] = &repoProjection{}

const ProjectionName = common.ProjectionName_ActionsRepoUsage

func (repoProjection) Name() common.ProjectionName   { return ProjectionName }
func (p repoProjection) Version() versioning.Version { return p.version }

func (p repoProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.GetKustoTableOrView(common.ReposTableType, aggInterval, p.version, p.scope, true)
}

func (p repoProjection) KustoQuery() *kql.Builder {
	return kql.New(`
		| summarize
			totalMinutes=sum(totalMinutes),
			jobExecutions=sum(jobExecutions),
			totalRunTime=sum(totalRunTime),
			totalQueueTime=sum(totalQueueTime),
			failures=sum(failures),
			totalFailureMinutes=sum(totalFailureMinutes),
			workflowExecutions=dcount_hll(hll_merge(workflowRunHll)),
			workflows=dcount_hll(hll_merge(workflowFilePathHll))
			by
        	repositoryOwnerId,
			repositoryId
		| extend
			averageRunTime=totalRunTime/jobExecutions,
			averageQueueTime=totalQueueTime/jobExecutions,
			failureRate=(toreal(failures) * 100)/toreal(jobExecutions)
	`)
}

func (p repoProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

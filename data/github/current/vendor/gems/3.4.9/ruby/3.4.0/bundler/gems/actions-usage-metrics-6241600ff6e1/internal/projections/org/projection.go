package org

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type OrgUsageItem struct {
	// Grouping
	RepositoryOwnerId string `json:"repositoryOwnerId" kusto:"repositoryOwnerId"`

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

type orgProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func OrgProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return orgProjection{version, scope}
}

var _ common.Projection[OrgUsageItem] = &orgProjection{}

const ProjectionName = common.ProjectionName_ActionsOrgUsage

func (orgProjection) Name() common.ProjectionName   { return ProjectionName }
func (p orgProjection) Version() versioning.Version { return p.version }

func (p orgProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.GetKustoTableOrView(common.OrgsTableType, aggInterval, p.version, p.scope, true)
}

func (p orgProjection) KustoQuery() *kql.Builder {
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
        	repositoryOwnerId
		| extend
			averageRunTime=totalRunTime/jobExecutions,
			averageQueueTime=totalQueueTime/jobExecutions,
			failureRate=(toreal(failures) * 100)/toreal(jobExecutions)
	`)
}

func (p orgProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

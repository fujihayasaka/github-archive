package summary

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type PerformanceSummaryItem struct {
	FailureRate         float64 `json:"failureRate" kusto:"failureRate"`
	AverageQueueTime    int64   `json:"averageQueueTime" kusto:"averageQueueTime"`
	AverageRunTime      int64   `json:"averageRunTime" kusto:"averageRunTime"`
	TotalFailureMinutes int64   `json:"totalFailureMinutes" kusto:"totalFailureMinutes"`
}

type performanceSummaryProjection struct {
	version     versioning.Version
	options     *proto.RequestOptions
	metricsType proto.MetricsType
}

func PerformanceSummaryProjection(version versioning.Version, options *proto.RequestOptions, metricsType proto.MetricsType) common.ProjectionInfo {
	return performanceSummaryProjection{
		version:     version,
		options:     options,
		metricsType: metricsType,
	}
}

var _ common.Projection[PerformanceSummaryItem] = &performanceSummaryProjection{}

func (performanceSummaryProjection) Name() common.ProjectionName   { return "ActionsPerformanceSummary" }
func (p performanceSummaryProjection) Version() versioning.Version { return p.version }

func (p performanceSummaryProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	tableType := common.GetSummaryTableType(p.options, p.metricsType)

	if tableType == common.WorkflowsTableType {
		// performance workflow table does not contain needed fields for summary so default to jobs tab
		tableType = common.JobsTableType
	}

	return common.GetKustoTableOrView(tableType, aggInterval, p.version, p.options.Scope, true)
}

func (p performanceSummaryProjection) KustoQuery() *kql.Builder {
	return getSummaryQuery(p.options, p.metricsType, p.version, p.options.Scope)
}

func (p performanceSummaryProjection) KustoSummarize() *kql.Builder {
	return kql.New(`
		| summarize
			totalFailureMinutes=sum(totalFailureMinutes),
			jobExecutions=sum(jobExecutions),
			totalQueueTime=sum(totalQueueTime),
			totalRunTime=sum(totalRunTime),
			failures=sum(failures)
		| extend
			averageRunTime=totalRunTime/jobExecutions,
			averageQueueTime=totalQueueTime/jobExecutions,
			failureRate=(toreal(failures) * 100)/toreal(jobExecutions)
	`)
}

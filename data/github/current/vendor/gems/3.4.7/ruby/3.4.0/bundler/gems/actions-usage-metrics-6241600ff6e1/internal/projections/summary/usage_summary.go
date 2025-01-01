package summary

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type UsageSummaryItem struct {
	TotalMinutes  int64 `json:"totalMinutes" kusto:"totalMinutes"`
	JobExecutions int64 `json:"jobExecutions" kusto:"jobExecutions"`
}

type usageSummaryProjection struct {
	version     versioning.Version
	options     *proto.RequestOptions
	metricsType proto.MetricsType
}

func UsageSummaryProjection(version versioning.Version, options *proto.RequestOptions, metricsType proto.MetricsType) common.ProjectionInfo {
	return usageSummaryProjection{
		version:     version,
		options:     options,
		metricsType: metricsType,
	}
}

var _ common.Projection[UsageSummaryItem] = &usageSummaryProjection{}

func (usageSummaryProjection) Name() common.ProjectionName   { return "ActionsUsageSummary" }
func (p usageSummaryProjection) Version() versioning.Version { return p.version }

func (p usageSummaryProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.GetKustoTableOrView(common.GetSummaryTableType(p.options, p.metricsType), aggInterval, p.version, p.options.Scope, true)
}

func (p usageSummaryProjection) KustoQuery() *kql.Builder {
	return getSummaryQuery(p.options, p.metricsType, p.version, p.options.Scope)

}

func (p usageSummaryProjection) KustoSummarize() *kql.Builder {
	return kql.New(`
		| summarize totalMinutes=sum(totalMinutes), jobExecutions=sum(jobExecutions)
	`)
}

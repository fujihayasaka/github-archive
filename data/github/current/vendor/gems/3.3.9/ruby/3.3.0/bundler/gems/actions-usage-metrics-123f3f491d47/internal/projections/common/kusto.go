package common

import (
	"fmt"
	"time"

	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/go-stats"
)

type KustoTableOrView struct {
	// Name of the table or view
	name               string
	isMaterializedView bool
}

type KustoTableType string

const (
	JobsTableType           KustoTableType = "jobs"
	ReposTableType          KustoTableType = "repos"
	RunnerRuntimesTableType KustoTableType = "runnerruntimes"
	RunnerTypesTableType    KustoTableType = "runnertypes"
	WorkflowsTableType      KustoTableType = "workflows"
	RunnerLabelsTableType   KustoTableType = "runnerlabels"
	RepoAppend              string         = "repo"
)

var metricsTypeToTableMapForSummary = map[proto.MetricsType]KustoTableType{
	// Map from proto key to kusto model field
	proto.MetricsType_METRICS_TYPE_JOB:            JobsTableType,
	proto.MetricsType_METRICS_TYPE_REPO:           ReposTableType,
	proto.MetricsType_METRICS_TYPE_RUNNER_RUNTIME: RunnerRuntimesTableType,
	proto.MetricsType_METRICS_TYPE_RUNNER_TYPE:    RunnerTypesTableType,
	proto.MetricsType_METRICS_TYPE_WORKFLOW:       JobsTableType,           // workflows does not work for summary due to missing columns so use jobs instead
	proto.MetricsType_METRICS_TYPE_UNKNOWN:        RunnerRuntimesTableType, // default to runtimes if unknown because it offers best performance
}

// Returns table or view name with proper append for scope. Noop for unsupported table types - only runnertype and runtime supported.
func GetTableTypeWithAppend(tableType KustoTableType, scope *proto.Scope) KustoTableType {
	if scope.ScopeType == proto.ScopeType_SCOPE_TYPE_REPO && (tableType == RunnerRuntimesTableType || tableType == RunnerTypesTableType) {
		return KustoTableType(fmt.Sprintf("%s_%s", tableType, RepoAppend))
	}

	return tableType
}

// QueryString returns the name of the table or view to be used in the query.
func (k KustoTableOrView) QueryString() string {
	if k.isMaterializedView {
		return fmt.Sprintf("materialized_view('%s')", k.name)
	}
	return k.name
}

// Name returns the raw name of the table or view.
func (k KustoTableOrView) Name() string {
	return k.name
}

var KustoComputeUsageBase = KustoTableOrView{
	name:               "ACTIONS_compute_usage_base",
	isMaterializedView: true,
}

var KustoComputeRepositoryNames = KustoTableOrView{
	name:               "GetLatestSnapshotView(github_mysql1_repositories)",
	isMaterializedView: false,
}

type KustoDelayTimes struct {
	// The delay from the event time to the time the event is available in Kusto
	KustoDelay time.Duration `json:"kustoDelay" kusto:"kustoDelay"`

	// The delay from the last materialized time to now
	MaterializedDelay time.Duration `json:"materializedDelay" kusto:"materializedDelay"`

	// The total delay from the event time to now
	TotalDelay time.Duration `json:"totalDelay" kusto:"totalDelay"`
}

func (k KustoDelayTimes) SendMetrics(statsClient stats.Client, tableName string) {
	tableTags := stats.Tags{
		telemetry.KustoTableNameTag: tableName,
	}
	statsClient.Gauge(telemetry.Kusto_KustoDelay_StatsKey, tableTags, k.KustoDelay.Milliseconds())
	statsClient.Gauge(telemetry.Kusto_MaterializedDelay_StatsKey, tableTags, k.MaterializedDelay.Milliseconds())
	statsClient.Gauge(telemetry.Kusto_TotalDelay_StatsKey, tableTags, k.TotalDelay.Milliseconds())
}

func GetKustoTableOrView(tableType KustoTableType, aggInterval ProjectionAggregationInterval, version versioning.Version, scope *proto.Scope, isMaterialized bool) KustoTableOrView {
	tableTypeWithAppend := GetTableTypeWithAppend(tableType, scope)

	if aggInterval != ProjectionAggregationIntervalNone {
		return KustoTableOrView{
			name:               fmt.Sprintf("ACTIONS_usage_%s_%s_%s", tableTypeWithAppend, aggInterval, version),
			isMaterializedView: isMaterialized,
		}
	} else {
		return KustoTableOrView{
			name:               fmt.Sprintf("ACTIONS_usage_%s_%s", tableTypeWithAppend, version),
			isMaterializedView: isMaterialized,
		}
	}
}

func GetKustoTableOrViewForPerformance(tableType KustoTableType, aggInterval ProjectionAggregationInterval, version versioning.Version, scope *proto.Scope, isMaterialized bool) KustoTableOrView {
	tableTypeWithAppend := GetTableTypeWithAppend(tableType, scope)

	if aggInterval != ProjectionAggregationIntervalNone {
		return KustoTableOrView{
			name:               fmt.Sprintf("ACTIONS_performance_%s_%s_%s", tableTypeWithAppend, aggInterval, version),
			isMaterializedView: isMaterialized,
		}
	} else {
		return KustoTableOrView{
			name:               fmt.Sprintf("ACTIONS_performance_%s_%s", tableTypeWithAppend, version),
			isMaterializedView: isMaterialized,
		}
	}
}

func GetSummaryTableType(options *proto.RequestOptions, metricsType proto.MetricsType) KustoTableType {
	view := RunnerRuntimesTableType

	if options.Filters != nil && len(options.Filters) > 0 {
		// if filters set then we want to use the materialized view based on the metrics type so filters can be applied
		// otherwise just stick with default view which offers best performance

		metricsView, ok := metricsTypeToTableMapForSummary[metricsType]
		if ok {
			view = metricsView
		}
	}

	return view
}

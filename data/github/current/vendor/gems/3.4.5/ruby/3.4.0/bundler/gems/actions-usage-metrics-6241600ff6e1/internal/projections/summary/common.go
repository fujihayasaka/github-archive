package summary

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/projections/job"
	"github.com/github/actions-usage-metrics/internal/projections/org"
	"github.com/github/actions-usage-metrics/internal/projections/repo"
	"github.com/github/actions-usage-metrics/internal/projections/runnerruntime"
	"github.com/github/actions-usage-metrics/internal/projections/runnertype"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

func getSummaryQuery(options *proto.RequestOptions, metricsType proto.MetricsType, version versioning.Version, scope *proto.Scope) *kql.Builder {
	if options.Filters != nil && len(options.Filters) > 0 && metricsType != proto.MetricsType_METRICS_TYPE_UNKNOWN {
		// if filters set then we want to use the query the will have matching filters
		// otherwise just return default and no query is needed

		if metricsType == proto.MetricsType_METRICS_TYPE_JOB {
			projection := job.JobProjection(version, scope)
			return projection.KustoQuery()
		}

		if metricsType == proto.MetricsType_METRICS_TYPE_REPO {
			projection := repo.RepoProjection(version, scope)
			return projection.KustoQuery()
		}

		if metricsType == proto.MetricsType_METRICS_TYPE_ORG {
			projection := org.OrgProjection(version, scope)
			return projection.KustoQuery()
		}

		if metricsType == proto.MetricsType_METRICS_TYPE_RUNNER_RUNTIME {
			projection := runnerruntime.RunnerRuntimeProjection(version, scope)
			return projection.KustoQuery()
		}

		if metricsType == proto.MetricsType_METRICS_TYPE_RUNNER_TYPE {
			projection := runnertype.RunnerTypeProjection(version, scope)
			return projection.KustoQuery()
		}

		if metricsType == proto.MetricsType_METRICS_TYPE_WORKFLOW {
			// workflow projections are missing fields required to generate the summary, so need to use job instead
			// because of this we need to cannot support filtering of summary data for certain workflow tab columns

			supportedFilters := []*proto.Filter{}
			for _, filter := range options.Filters {
				if !common.FilterIsUnsupportForSummaryInWorkflows(filter.GetKey()) {
					supportedFilters = append(supportedFilters, filter)
				}
			}

			options.Filters = supportedFilters
			projection := job.JobProjection(version, scope)
			return projection.KustoQuery()
		}
	}

	return kql.New("")
}

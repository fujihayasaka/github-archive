package autocomplete

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type jobsProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func JobsProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return jobsProjection{version, scope}
}

var _ common.Projection[AutoCompleteItem] = &jobsProjection{}

func (jobsProjection) Name() common.ProjectionName   { return "ActionsJobsAutocomplete" }
func (p jobsProjection) Version() versioning.Version { return p.version }

func (p jobsProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.GetKustoTableOrView(common.JobsTableType, aggInterval, p.version, p.scope, true)
}

func (jobsProjection) KustoQuery() *kql.Builder {
	return kql.New(`
		| extend jobName=base64_decode_tostring(jobName)
	`)
}

func (p jobsProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

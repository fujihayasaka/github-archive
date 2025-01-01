package autocomplete

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type runnerLabelsProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func RunnerLabelsProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return runnerLabelsProjection{version, scope}
}

var _ common.Projection[AutoCompleteItem] = &runnerLabelsProjection{}

func (runnerLabelsProjection) Name() common.ProjectionName   { return "ActionsRunnerLabelsAutocomplete" }
func (p runnerLabelsProjection) Version() versioning.Version { return p.version }

func (p runnerLabelsProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	v := p.version

	if v == versioning.V2 {
		v = versioning.V3 // this query only works on V3 or later
	}

	return common.GetKustoTableOrView(common.RunnerLabelsTableType, common.ProjectionAggregationIntervalNone, v, p.scope, true)
}

func (runnerLabelsProjection) KustoQuery() *kql.Builder {
	return kql.New("") // table is ready to just read data from, no additional query needed
}

func (p runnerLabelsProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

package autocomplete

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type workflowsProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func WorkflowsProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return workflowsProjection{version, scope}
}

var _ common.Projection[AutoCompleteItem] = &workflowsProjection{}

func (workflowsProjection) Name() common.ProjectionName   { return "ActionsWorkflowsAutocomplete" }
func (p workflowsProjection) Version() versioning.Version { return p.version }

func (p workflowsProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.GetKustoTableOrView(common.WorkflowsTableType, aggInterval, p.version, p.scope, true)
}

func (workflowsProjection) KustoQuery() *kql.Builder {
	return kql.New(`
		| extend workflowFileName = tostring(split(base64_decode_tostring(workflowFilePath), "/")[-1])
	`)
}

func (p workflowsProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

package common

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type ProjectionName string

const (
	ProjectionName_ActionsJobUsage           ProjectionName = "ActionsJobUsage"
	ProjectionName_ActionsWorkflowUsage      ProjectionName = "ActionsWorkflowUsage"
	ProjectionName_ActionsRepoUsage          ProjectionName = "ActionsRepoUsage"
	ProjectionName_ActionsRunnerRuntimeUsage ProjectionName = "ActionsRunnerRuntimeUsage"
	ProjectionName_ActionsRunnerTypeUsage    ProjectionName = "ActionsRunnerTypeUsage"
	ProjectionName_RepositoryNames           ProjectionName = "RepositoryNames"
)

func (p ProjectionName) String() string {
	return string(p)
}

type ProjectionInfo interface {
	Name() ProjectionName
	Version() versioning.Version

	// Kusto
	KustoTableOrView(aggInterval ProjectionAggregationInterval) KustoTableOrView
	KustoQuery() *kql.Builder     // query comes before filters
	KustoSummarize() *kql.Builder // summarize comes after filters and query
}

type Projection[TItem any] interface {
	ProjectionInfo
}

type GetProjectionFunc func(version versioning.Version, scope *proto.Scope) ProjectionInfo

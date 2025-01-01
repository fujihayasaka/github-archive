package repository_names

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type RepositoryItem struct {
	Name string `json:"name" kusto:"name"`
	Id   int64  `json:"id" kusto:"id"`
}

type repositoryNamesProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func RepositoryNamesProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return repositoryNamesProjection{version, scope}
}

var _ common.Projection[RepositoryItem] = &repositoryNamesProjection{}

const ProjectionName = common.ProjectionName_RepositoryNames

func (repositoryNamesProjection) Name() common.ProjectionName   { return ProjectionName }
func (p repositoryNamesProjection) Version() versioning.Version { return p.version }

func (repositoryNamesProjection) KustoTableOrView(_ common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.KustoRepositoryNamesTable
}

func (repositoryNamesProjection) KustoQuery() *kql.Builder {
	return KustoQuery()
}

func KustoQuery() *kql.Builder {
	return kql.New(`
		| extend id=toint(id)
		| project name, id
	`)
}

func (p repositoryNamesProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

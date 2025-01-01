package org_names

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type OrgItem struct {
	Name string `json:"display_login" kusto:"display_login"`
	Id   int64  `json:"id" kusto:"id"`
}

type orgNamesProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func OrgNamesProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return orgNamesProjection{version, scope}
}

var _ common.Projection[OrgItem] = &orgNamesProjection{}

const ProjectionName = common.ProjectionName_OrgNames

func (orgNamesProjection) Name() common.ProjectionName   { return ProjectionName }
func (p orgNamesProjection) Version() versioning.Version { return p.version }

func (orgNamesProjection) KustoTableOrView(_ common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.KustoOrgNamesTable
}

func (orgNamesProjection) KustoQuery() *kql.Builder {
	return KustoQuery()
}

func KustoQuery() *kql.Builder {
	return kql.New(`
		| extend id=toint(id)
		| project display_login, id
	`)
}

func (p orgNamesProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}

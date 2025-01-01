package org_names

import (
	"context"
	"fmt"

	"github.com/github/actions-usage-metrics/internal/kusto"
	"github.com/github/actions-usage-metrics/internal/kusto/query"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

func QueryOrgNames(
	ctx context.Context,
	scope *proto.Scope) (*common.QueryResult[OrgItem], error) {
	ctx, span := telemetry.Trace(ctx, "kustoReader.QueryOrgNames")
	defer span.End()

	client := kusto.GetKustoClient()
	logger := log.WithContext(ctx)

	scopeOptions := query.QueryOptions{
		Scope: scope,
	}

	span.AddEvent("queryOrgItems")
	logger.Info("Executing kusto query on orgs")
	queryProvider := query.NewKustoOrgNamesQueryBuilder(common.KustoOrgNamesTable.Name(), KustoQuery(), scopeOptions)
	query := queryProvider.Build()
	logger.Debug("Query", kvp.String(telemetry.OTelKeyQuery, query.Query().String()), kvp.Any(telemetry.OTelKeyParams, query.Parameters().ToParameterCollection()))

	items, err := kusto.QuerySnapshots[OrgItem](ctx, client, queryProvider)
	if err != nil {
		return nil, fmt.Errorf("failed to query kusto for org name items: %w", err)
	}

	return &common.QueryResult[OrgItem]{
		Items:      items,
		TotalItems: uint64(len(items)),
		More:       false,
	}, nil
}

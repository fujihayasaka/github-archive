package repository_names

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

func QueryRepositoryNames(
	ctx context.Context,
	scope *proto.Scope) (*common.QueryResult[RepositoryItem], error) {
	ctx, span := telemetry.Trace(ctx, "kustoReader.QueryRepositoryNames")
	defer span.End()

	client := kusto.GetKustoClient()
	logger := log.WithContext(ctx)

	scopeOptions := query.QueryOptions{
		Scope: scope,
	}

	span.AddEvent("queryRepoItems")
	logger.Info("Executing kusto query on repos")
	queryProvider := query.NewKustoRepositoryNamesQueryBuilder(common.KustoRepositoryNamesTable.Name(), KustoQuery(), scopeOptions)
	query := queryProvider.Build()
	logger.Debug("Query", kvp.String(telemetry.OTelKeyQuery, query.Query().String()), kvp.Any(telemetry.OTelKeyParams, query.Parameters().ToParameterCollection()))

	items, err := kusto.QuerySnapshots[RepositoryItem](ctx, client, queryProvider)
	if err != nil {
		return nil, fmt.Errorf("failed to query kusto for repo name items: %w", err)
	}

	return &common.QueryResult[RepositoryItem]{
		Items:      items,
		TotalItems: uint64(len(items)),
		More:       false,
	}, nil
}

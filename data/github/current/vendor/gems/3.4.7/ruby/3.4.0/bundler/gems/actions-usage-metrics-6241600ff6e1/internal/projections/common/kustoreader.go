package common

import (
	"context"
	"fmt"

	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/kusto"
	"github.com/github/actions-usage-metrics/internal/kusto/query"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

type kustoReader[TItem any] struct {
	projection  ProjectionInfo
	kustoClient *kusto.Client
	telem       *telemetry.Telemetry
	aggInterval ProjectionAggregationInterval
}

func NewKustoReader[TItem any](kustoClient *kusto.Client, projection ProjectionInfo, aggInterval ProjectionAggregationInterval, telem *telemetry.Telemetry) (*kustoReader[TItem], error) {
	if kustoClient == nil {
		return nil, fmt.Errorf("kustoClient is required")
	}
	return &kustoReader[TItem]{
		projection:  projection,
		aggInterval: aggInterval,
		kustoClient: kustoClient,
		telem:       telem,
	}, nil
}

func (r *kustoReader[TItem]) QueryUsageItems(
	ctx context.Context,
	queryOptions query.QueryOptions) (*QueryResult[TItem], error) {

	ctx, span := telemetry.Trace(ctx, "kustoReader.QueryUsageItems")
	defer span.End()

	logger := log.WithContext(ctx)
	totalCount := uint64(0)

	span.AddEvent("queryItems")
	logger.Info("Executing kusto query")
	queryProvider := BuildKustoQuery(r.projection, r.aggInterval, queryOptions)
	query := queryProvider.Build()
	logger.Debug("Query", kvp.String(telemetry.OTelKeyQuery, query.Query().String()), kvp.Any(telemetry.OTelKeyParams, query.Parameters().ToParameterCollection()))

	items, count, err := kusto.QueryRowsAndCount[TItem](ctx, r.kustoClient, queryProvider)
	if err != nil {
		return nil, fmt.Errorf("failed to query kusto for items: %w", err)
	}

	if count != nil {
		totalCount = uint64(*count)
	}

	return &QueryResult[TItem]{
		Items:      items,
		TotalItems: totalCount,
		More:       false,
	}, nil
}

func (r *kustoReader[TItem]) QueryKustoDelayTimes(ctx context.Context) (KustoDelayTimes, error) {
	ctx, span := telemetry.Trace(ctx, "kustoReader.QueryKustoDelayTimes")
	defer span.End()
	logger := log.WithContext(ctx)

	tableOrView := r.projection.KustoTableOrView(r.aggInterval)

	aggQuery := kql.New("").AddLiteral("let kustoDelay = toscalar(").AddTable("RestrictedView").AddLiteral(" | where timestamp > ago(3d) | summarize Delay=now()-max(completed_at));\n").
		AddLiteral("let materializedDelay = toscalar(").AddTable("$command_results").AddLiteral(" | extend Delay=now()-MaterializedTo | project Delay);\n").
		AddLiteral("let totalDelay = kustoDelay + materializedDelay;\n").
		AddLiteral("print totalDelay=totalDelay, materializedDelay=materializedDelay, kustoDelay=kustoDelay")

	qb := query.NewKustoQueryBuilderNoTenant(KustoComputeUsageBase.QueryString(), []query.AllowedNoTenantField{query.CompletedAt, query.Timestamp}, true, aggQuery)
	qb.SetShowMaterializedViewCommand(tableOrView.Name())
	query := qb.Build()

	logger.Debug("Delay times query", kvp.String(telemetry.OTelKeyQuery, query.Query().String()))

	rows, err := kusto.QueryRowsMgmt[KustoDelayTimes](ctx, r.kustoClient, qb)
	if err != nil {
		return KustoDelayTimes{}, fmt.Errorf("failed to query kusto for delays: %w", err)
	}

	if len(rows) != 1 {
		return KustoDelayTimes{}, fmt.Errorf("expected 1 row, got %d", len(rows))
	}

	delayTimes := rows[0]
	delayTimes.SendMetrics(r.telem.Stats, tableOrView.Name())
	logger.Info("Kusto delay times",
		kvp.String(telemetry.OTelKeyTableOrView, tableOrView.Name()),
		kvp.Duration(telemetry.OTelKeyKustoDelay, delayTimes.KustoDelay),
		kvp.Duration(telemetry.OTelKeyMaterializedDelay, delayTimes.MaterializedDelay),
		kvp.Duration(telemetry.OTelKeyTotalDelay, delayTimes.TotalDelay),
	)

	return delayTimes, nil
}

// BuildKustoQuery helps builds a query with all the possible (optional) bells and whistles.
func BuildKustoQuery(
	projection ProjectionInfo,
	aggInterval ProjectionAggregationInterval,
	queryOptions query.QueryOptions) query.QueryProvider {
	tableOrView := projection.KustoTableOrView(aggInterval)
	qb := query.NewKustoQueryBuilder(tableOrView.QueryString(), projection.KustoQuery(), queryOptions)
	if queryOptions.Filters != nil {
		qb.SetFilters(*queryOptions.Filters)
	}
	if queryOptions.OrderBy != nil && queryOptions.Search == nil {
		// only add order by if no search, since search has it's own ordering
		qb.SetOrderBy(*queryOptions.OrderBy)
	}
	if queryOptions.Search != nil {
		qb.SetSearch(*queryOptions.Search)
	}
	if queryOptions.OffsetLimit != nil {
		// only set offsetLimit if it exists
		qb.SetOffsetLimit(*queryOptions.OffsetLimit)
	}

	qb.SetSummarize(projection.KustoSummarize())

	return qb
}

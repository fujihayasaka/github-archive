package kusto

import (
	"context"
	"fmt"

	"github.com/Azure/azure-kusto-go/azkustodata"
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	kquery "github.com/Azure/azure-kusto-go/azkustodata/query"
	v2 "github.com/Azure/azure-kusto-go/azkustodata/query/v2"
	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/internal/kusto/query"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/github-telemetry-go/log"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type Client struct {
	client *azkustodata.Client
	db     string
	repoDb string
}

var kusto_client Client

func NewKustoClient(cfg config.KustoConfig) (*Client, error) {
	connectionStringBuilder := azkustodata.NewConnectionStringBuilder(cfg.ConnectionString)

	if cfg.IsDev && len(cfg.ClientSecret) == 0 {
		log.Warn("Using Azure CLI credential for development environment.")
		connectionStringBuilder = connectionStringBuilder.WithAzCli()
	} else {
		connectionStringBuilder = connectionStringBuilder.WithAadAppKey(cfg.ClientId, cfg.ClientSecret, cfg.TenantId) // CI, lab or prod
	}

	client, err := azkustodata.New(connectionStringBuilder)
	if err != nil {
		return nil, err
	}

	kusto_client = Client{client, cfg.Database, cfg.RepoDatabase}

	return &kusto_client, nil
}

func GetKustoClient() *Client {
	return &kusto_client
}

func (c *Client) Close() error {
	return c.client.Close()
}

func (c *Client) TestConnection(ctx context.Context) error {
	_, err := c.client.Query(ctx, c.db, kql.New("print 1"))
	return err
}

func (c *Client) TestConnectionRepos(ctx context.Context) error {
	_, err := c.client.Query(ctx, c.repoDb, kql.New("print 1"))
	return err
}

func QueryRows[T any](ctx context.Context, client *Client, queryProvider query.QueryProvider) ([]T, error) {
	ctx, span := telemetry.Trace(ctx, "kusto.QueryRows")
	defer span.End()

	response, err := queryWithMetadata[T](ctx, client, queryProvider, client.db)
	if err != nil {
		return nil, fmt.Errorf("failed to query kusto: %w", err)
	}

	span.AddEvent("toStructs")
	rows, err := kquery.ToStructs[T](response)
	if err != nil {
		return nil, fmt.Errorf("failed to convert kusto response to structs: %w", err)
	}

	return rows, nil
}

func QueryRepositoryRows[T any](ctx context.Context, client *Client, queryProvider query.QueryProvider) ([]T, error) {
	ctx, span := telemetry.Trace(ctx, "kusto.QueryRepositoryRows")
	defer span.End()

	response, err := queryWithMetadata[T](ctx, client, queryProvider, client.repoDb)
	if err != nil {
		return nil, fmt.Errorf("failed to query kusto repos: %w", err)
	}

	span.AddEvent("toStructs")
	rows, err := kquery.ToStructs[T](response)
	if err != nil {
		return nil, fmt.Errorf("failed to convert kusto repos response to structs: %w", err)
	}

	return rows, nil
}

func QueryRowsMgmt[T any](ctx context.Context, client *Client, queryProvider query.QueryProvider) ([]T, error) {
	ctx, span := telemetry.Trace(ctx, "kusto.QueryRowsMgmt")
	defer span.End()

	query := queryProvider.Build()
	span.AddEvent("mgmt")
	response, err := client.client.Mgmt(ctx, client.db, query.Query(), azkustodata.QueryParameters(query.Parameters()), getClientRequestIdQueryOption(span))
	if err != nil {
		return nil, fmt.Errorf("failed to query kusto with management command: %w", err)
	}

	span.AddEvent("toStructs")
	rows, err := kquery.ToStructs[T](response)
	if err != nil {
		return nil, fmt.Errorf("failed to convert kusto response to structs: %w", err)
	}

	// Extract status from response and add to span
	span.AddEvent("status")
	if len(response.Status()) > 0 {
		status := response.Status()[0]
		span.SetAttributes(
			attribute.String("status.activityid", status.ActivityId.String()),
			attribute.String("status.clientactivityid", status.ClientActivityId),
			attribute.Int("status.count", int(status.Count)),
			attribute.String("status.requestid", status.RequestId.String()),
			attribute.Int("status.severity", int(status.Severity)),
			attribute.String("status.severityname", status.SeverityName),
			attribute.Int("status.statuscode", int(status.StatusCode)),
			attribute.String("status.statusdescription", status.StatusDescription),
			attribute.String("status.subactivityid", status.SubActivityId.String()),
			attribute.String("status.timestamp", status.Timestamp.String()),
		)
	}

	return rows, nil
}

func QueryValue[T any](ctx context.Context, client *Client, queryProvider query.QueryProvider) (T, error) {
	ctx, span := telemetry.Trace(ctx, "kusto.QueryValue")
	defer span.End()

	values, err := QueryValues[T](ctx, client, queryProvider)
	if err != nil {
		return *new(T), fmt.Errorf("failed to get value %w", err)
	}

	if len(values) == 0 {
		return *new(T), fmt.Errorf("no val in row")
	}

	return values[0], nil
}

func QueryValues[T any](ctx context.Context, client *Client, queryProvider query.QueryProvider) ([]T, error) {
	ctx, span := telemetry.Trace(ctx, "kusto.QueryValues")
	defer span.End()

	response, err := queryWithMetadata[T](ctx, client, queryProvider, client.db)
	if err != nil {
		return nil, fmt.Errorf("failed to query kusto: %w", err)
	}

	span.AddEvent("tables")
	tables := response.Tables()
	if len(tables) == 0 {
		return *new([]T), fmt.Errorf("no tables in response")
	}

	span.AddEvent("rows")
	rows := tables[0].Rows()
	result := make([]T, 0)
	for _, row := range rows {
		rowVal, err := row.Value(0)
		val := rowVal.GetValue()

		typedVal, ok := val.(T)
		if !ok {
			return *new([]T), fmt.Errorf("failed to convert kusto value of type %T to type %T", val, typedVal)
		}

		if err != nil {
			return *new([]T), fmt.Errorf("no val in row: %w", err)
		}
		result = append(result, typedVal)
	}

	return result, nil
}

// queryWithMetadata is a helper function that queries Kusto and extracts metadata from the response and adds it to the span.
func queryWithMetadata[T any](ctx context.Context, client *Client, queryProvider query.QueryProvider, database string) (kquery.Dataset, error) {
	ctx, span := telemetry.Trace(ctx, "kusto.queryWithMetadata")
	defer span.End()

	span.AddEvent("iterativeQuery")
	query := queryProvider.Build()
	iterativeDataset, err := client.client.IterativeQuery(ctx, database, query.Query(), azkustodata.QueryParameters(query.Parameters()), getClientRequestIdQueryOption(span))
	if err != nil {
		return nil, err
	}

	span.AddEvent("tableResults")
	var tables []kquery.Table
	for tableResult := range iterativeDataset.Tables() {
		// You can access iterativeTable metadata, such as the iterativeTable name
		iterativeTable := tableResult.Table()
		table, err := iterativeTable.ToTable()
		if err != nil {
			return nil, err
		}
		span.AddEvent(iterativeTable.Name())
		tables = append(tables, table)
		if !iterativeTable.IsPrimaryResult() {
			switch iterativeTable.Kind() {
			case v2.QueryCompletionInformationKind:
				queryCompletionInfos, err := v2.AsQueryCompletionInformation(iterativeTable)
				if err == nil {
					queryCompletionInfo := queryCompletionInfos[0]
					span.SetAttributes(
						attribute.String("querycompletion.activityid", queryCompletionInfo.ActivityId.String()),
						attribute.String("querycompletion.clientrequestid", queryCompletionInfo.ClientRequestId),
						attribute.Int("querycompletion.eventtype", queryCompletionInfo.EventType),
						attribute.String("querycompletion.eventtypename", queryCompletionInfo.EventTypeName),
						attribute.Int("querycompletion.level", queryCompletionInfo.Level),
						attribute.String("querycompletion.levelname", queryCompletionInfo.LevelName),
						attribute.String("querycompletion.parentactivityid", queryCompletionInfo.ParentActivityId.String()),
						attribute.String("querycompletion.payload", queryCompletionInfo.Payload),
						attribute.Int("querycompletion.statuscode", queryCompletionInfo.StatusCode),
						attribute.String("querycompletion.statuscodename", queryCompletionInfo.StatusCodeName),
						attribute.String("querycompletion.subactivityid", queryCompletionInfo.SubActivityId.String()),
						attribute.String("querycompletion.timestamp", queryCompletionInfo.Timestamp.String()),
					)
				}
			}
		}
	}

	// Return a new dataset so calling functions can iterate over the tables again
	return kquery.NewDataset(iterativeDataset, tables), nil
}

func getClientRequestIdQueryOption(span trace.Span) azkustodata.QueryOption {
	// We recommend using the format ClientApplicationName.ActivityType;UniqueId
	spanContext := span.SpanContext()
	clientRequestID := fmt.Sprintf("actions-usage-metrics.execute;%s-%s", spanContext.TraceID().String(), spanContext.SpanID().String())
	return azkustodata.ClientRequestID(clientRequestID)
}

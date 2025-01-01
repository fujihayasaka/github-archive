package cosmos

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

// Querier represents a CosmosDB query engine.
type Querier[ResultType any] struct {
	dbConnection ReadWriter
	tracer       trace.Tracer
}

// NewQuerier creates a new Querier.
func NewQuerier[ResultType any](dbConnection ReadWriter) *Querier[ResultType] {
	// We create a new named tracer from the global tracer provider to delineate the CosmosDB operations.
	tracer := otel.Tracer("cosmosdb", trace.WithSchemaURL(semconv.SchemaURL))
	return &Querier[ResultType]{
		dbConnection: dbConnection,
		tracer:       tracer,
	}
}

// ExecuteQuery executes a query against a CosmosDB container and unmarshals the results into the provided ResultType.
func (q *Querier[ResultType]) ExecuteQuery(ctx context.Context, query, partitionKey string, o *azcosmos.QueryOptions) ([]ResultType, error) {
	ctx, sp := q.tracer.Start(ctx, "SELECT",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			semconv.DBSystemCosmosDB,
			semconv.DBNamespace(q.dbConnection.DatabaseName()),
			semconv.DBCollectionName(q.dbConnection.ContainerName()),
			semconv.DBOperationName("SELECT"),
			attribute.String("db.cosmosdb.operation_type", "Query"),
			attribute.String("db.cosmosdb.partition_key", partitionKey),
			semconv.DBQueryText(query),
		),
	)
	defer sp.End()

	queryPager := q.dbConnection.NewQueryItemsPager(query, azcosmos.NewPartitionKeyString(partitionKey), o)
	items := make([]ResultType, 0)
	var totalRequestCharge float32

	for queryPager.More() {
		err := func() error { // Use a closure so we can defer the inner span end.
			_, pageSp := q.tracer.Start(ctx, "Query Page")
			defer pageSp.End()

			queryResponse, err := queryPager.NextPage(ctx)
			if err != nil {
				recordError(err, pageSp)
				return fmt.Errorf("failed to query page: %w", err)
			}

			pageSp.SetAttributes(
				attribute.Int("db.row_count", len(queryResponse.Items)),
				semconv.DBCosmosDBRequestCharge(float64(queryResponse.RequestCharge)),
			)

			totalRequestCharge += queryResponse.RequestCharge

			for _, item := range queryResponse.Items {
				var itemResponseBody ResultType
				err := json.Unmarshal(item, &itemResponseBody)
				if err != nil {
					recordError(err, pageSp)
					return fmt.Errorf("failed to unmarshal item: %w", err)
				}
				items = append(items, itemResponseBody)
			}
			return nil
		}()

		if err != nil {
			recordError(err, sp)
			return nil, err
		}
	}
	sp.SetAttributes(
		attribute.Int("db.row_count", len(items)),
		semconv.DBCosmosDBRequestCharge(float64(totalRequestCharge)),
	)

	return items, nil
}

func recordError(err error, span trace.Span) {
	span.RecordError(err)
	span.SetStatus(codes.Error, err.Error())
}

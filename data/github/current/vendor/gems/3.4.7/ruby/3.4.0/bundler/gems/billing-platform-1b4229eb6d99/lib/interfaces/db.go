package interfaces

import (
	"context"
	"sync"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"

	"go.opentelemetry.io/otel/trace"
)

type QueryOptions struct {
	IncludeBudgetStoredProcedure   bool
	IncludeTotalStoredProcedure    bool
	IgnoreExistingDocumentError    bool
	RetryCount                     int
	IfMatchEtag                    *azcore.ETag
	ConsistencyLevel               *azcosmos.ConsistencyLevel
	DedicatedGatewayRequestOptions *azcosmos.DedicatedGatewayRequestOptions
}

type RepositoryUpdateHandlerDatabase interface {
	UpsertWithOptions(ctx context.Context, logger log.Logger, item models.ItemKey, options *QueryOptions) error
}

type PatchOps = azcosmos.PatchOperations

//go:generate pegomock generate -o ../../testing/fakes/mock_database.go --self_package=fakes --package=fakes Database
type Database interface {
	Batch(
		ctx context.Context,
		item models.ItemKey,
		opts *QueryOptions,
		doBatchItems func(*azcosmos.TransactionalBatch) error) (bool, []azcosmos.TransactionalBatchResult, error)
	GetTotals(ctx context.Context, logger log.Logger, query, pk string) (*models.Amounts, error)
	GetUsageTotals(ctx context.Context, logger log.Logger, pk string) (*models.Amounts, error)
	GetUsageTotalsWithQuantity(ctx context.Context, logger log.Logger, pk string) (*models.Amounts, error)
	GetDiscountTotals(ctx context.Context, logger log.Logger, pk string) (*models.Amounts, error)
	Exists(ctx context.Context, logger log.Logger, key models.ItemKey, opts *QueryOptions) (bool, error)
	DeleteAsync(ctx context.Context, logger log.Logger, key models.ItemKey, wg *sync.WaitGroup, errors chan<- error)
	DeleteWithOptions(ctx context.Context, logger log.Logger, key models.ItemKey, options *QueryOptions) error
	UpsertAsync(ctx context.Context, logger log.Logger, item models.ItemKey, wg *sync.WaitGroup, opts *QueryOptions, errors chan<- error)
	UpsertWithOptions(ctx context.Context, logger log.Logger, item models.ItemKey, options *QueryOptions) error
	CreateAsync(ctx context.Context, logger log.Logger, item models.ItemKey, wg *sync.WaitGroup, opts *QueryOptions, errors chan<- error)
	CreateIfNotExists(ctx context.Context, logger log.Logger, item models.ItemKey) (bool, error)
	CreateIfNotExistAsync(ctx context.Context, logger log.Logger, item models.ItemKey, wg *sync.WaitGroup, opts *QueryOptions, errors chan<- error)
	CreateWithOptions(ctx context.Context, logger log.Logger, item models.ItemKey, options *QueryOptions) error
	PatchWithOptions(ctx context.Context, logger log.Logger, item models.ItemKey, patchOps PatchOps, options *QueryOptions) error

	GetConnection() CosmosConnection
	GetGatewayConnection() CosmosConnection
	GetTracer() trace.Tracer
	GetStatter() stats.Client
	SetStatterTags(tags stats.Tags)
}

type Querier[T any] interface {
	ReadItem(ctx context.Context, logger log.Logger, key models.ItemKey, options *QueryOptions) (T, error)
	QueryItems(ctx context.Context, logger log.Logger, query string, pk string) ([]T, error)
	QueryItemsWithOptions(ctx context.Context, logger log.Logger, query string, pk string, retryCount int, options *azcosmos.QueryOptions) ([]T, error)
}

type CosmosConnection interface {
	DocumentInteractor

	NewTransactionalBatch(azcosmos.PartitionKey) azcosmos.TransactionalBatch
	ExecuteTransactionalBatch(context.Context, azcosmos.TransactionalBatch, *azcosmos.TransactionalBatchOptions) (azcosmos.TransactionalBatchResponse, error)
}

type DocumentInteractor interface {
	CreateItem(ctx context.Context, partitionKey azcosmos.PartitionKey, item []byte, ops *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)
	PatchItem(ctx context.Context, partitionKey azcosmos.PartitionKey, id string, ops azcosmos.PatchOperations, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)
	DeleteItem(ctx context.Context, partitionKey azcosmos.PartitionKey, id string, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)
	UpsertItem(ctx context.Context, partitionKey azcosmos.PartitionKey, item []byte, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)
	ReadItem(ctx context.Context, partitionKey azcosmos.PartitionKey, id string, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)

	NewQueryItemsPager(query string, partitionKey azcosmos.PartitionKey, options *azcosmos.QueryOptions) *runtime.Pager[azcosmos.QueryItemsResponse]
}

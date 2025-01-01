package mocks

import (
	"context"
	"net/http/httptest"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
)

type CosmosConnection struct {

	// CreateItemFunc
	CreateItemFunc func(context.Context, azcosmos.PartitionKey, []byte, *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)

	// PatchItemFunc
	PatchItemFunc func(context.Context, azcosmos.PartitionKey, string, azcosmos.PatchOperations, *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)

	// DeleteItemFunc
	DeleteItemFunc func(context.Context, azcosmos.PartitionKey, string, *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)

	// UpsertItemFunc
	UpsertItemFunc func(context.Context, azcosmos.PartitionKey, []byte, *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)

	// ReadItemFunc
	ReadItemFunc func(context.Context, azcosmos.PartitionKey, string, *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)

	// NewQueryItemsPagerFunc
	NewQueryItemsPagerFunc func(string, azcosmos.PartitionKey, *azcosmos.QueryOptions) *runtime.Pager[azcosmos.QueryItemsResponse]

	// NewTransactionalBatchFunc
	NewTransactionalBatchFunc func(azcosmos.PartitionKey) azcosmos.TransactionalBatch

	// ExecuteTransactionalBatchFunc
	ExecuteTransactionalBatchFunc func(context.Context, azcosmos.TransactionalBatch, *azcosmos.TransactionalBatchOptions) (azcosmos.TransactionalBatchResponse, error)
}

func (c *CosmosConnection) CreateItem(_ context.Context, _ azcosmos.PartitionKey, _ []byte, _ *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	if c.CreateItemFunc != nil {
		return c.CreateItemFunc(context.Background(), azcosmos.PartitionKey{}, []byte{}, &azcosmos.ItemOptions{})
	}
	return azcosmos.ItemResponse{}, nil
}

func (c *CosmosConnection) PatchItem(ctx context.Context, pk azcosmos.PartitionKey, id string, operations azcosmos.PatchOperations, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	if c.PatchItemFunc != nil {
		return c.PatchItemFunc(ctx, pk, id, operations, options)
	}

	return azcosmos.ItemResponse{}, nil
}

// DeleteItem
func (c *CosmosConnection) DeleteItem(_ context.Context, _ azcosmos.PartitionKey, _ string, _ *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	if c.DeleteItemFunc != nil {
		return c.DeleteItemFunc(context.Background(), azcosmos.PartitionKey{}, "", &azcosmos.ItemOptions{})
	}
	return azcosmos.ItemResponse{}, nil
}

// UpsertItem
func (c *CosmosConnection) UpsertItem(_ context.Context, _ azcosmos.PartitionKey, _ []byte, _ *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	if c.UpsertItemFunc != nil {
		return c.UpsertItemFunc(context.Background(), azcosmos.PartitionKey{}, []byte{}, &azcosmos.ItemOptions{})
	}
	return azcosmos.ItemResponse{}, nil
}

// ReadItem
func (c *CosmosConnection) ReadItem(_ context.Context, _ azcosmos.PartitionKey, _ string, _ *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	if c.ReadItemFunc != nil {
		return c.ReadItemFunc(context.Background(), azcosmos.PartitionKey{}, "", &azcosmos.ItemOptions{})
	}

	return azcosmos.ItemResponse{}, nil
}

// NewQueryItemsPager
func (c *CosmosConnection) NewQueryItemsPager(_ string, _ azcosmos.PartitionKey, _ *azcosmos.QueryOptions) *runtime.Pager[azcosmos.QueryItemsResponse] {
	if c.NewQueryItemsPagerFunc != nil {
		return c.NewQueryItemsPagerFunc("", azcosmos.PartitionKey{}, &azcosmos.QueryOptions{})
	}
	return nil
}

// NewTransactionalBatch
func (c *CosmosConnection) NewTransactionalBatch(_ azcosmos.PartitionKey) azcosmos.TransactionalBatch {
	if c.NewTransactionalBatchFunc != nil {
		return c.NewTransactionalBatchFunc(azcosmos.PartitionKey{})
	}
	return azcosmos.TransactionalBatch{}
}

// ExecuteTransactionalBatch
func (c *CosmosConnection) ExecuteTransactionalBatch(_ context.Context, _ azcosmos.TransactionalBatch, _ *azcosmos.TransactionalBatchOptions) (azcosmos.TransactionalBatchResponse, error) {
	if c.ExecuteTransactionalBatchFunc != nil {
		return c.ExecuteTransactionalBatchFunc(context.Background(), azcosmos.TransactionalBatch{}, &azcosmos.TransactionalBatchOptions{})
	}
	return azcosmos.TransactionalBatchResponse{}, nil
}

// Not Found Error
var AzureNotFoundErr = NewResponseError("NotFound", 404)

// Conflict Error
var AzureConflictErr = NewResponseError("Conflict", 409)

// RateLimit Error
var AzureRateLimitErr = NewResponseError("RateLimit", 429)

func NewResponseError(errorCode string, statusCode int) *azcore.ResponseError {
	w := httptest.NewRecorder()
	w.WriteHeader(statusCode)
	response := w.Result()
	response.Request = httptest.NewRequest("GET", "http://mockme.com", nil)
	defer response.Body.Close()

	return &azcore.ResponseError{
		ErrorCode:   errorCode,
		StatusCode:  statusCode,
		RawResponse: response,
	}
}

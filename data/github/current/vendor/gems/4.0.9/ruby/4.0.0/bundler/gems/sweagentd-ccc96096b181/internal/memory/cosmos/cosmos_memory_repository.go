// Package cosmos provides a Cosmos DB implementation of the memory repository.
package cosmos

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
)

// Telemetry metric names for Cosmos repository operations.
const (
	metricCosmosOperationDuration = "memory_cosmos.operation_duration"
	metricCosmosErrorCount        = "memory_cosmos.error_count"
	metricCosmosPayloadSize       = "memory_cosmos.payload_size"
)

// cosmosMemoryRepository implements the core.MemoryRepository interface using Cosmos DB.

type cosmosMemoryRepository struct {
	container *azcosmos.ContainerClient
	obsv      observability.Exporters
}

// Ensure that cosmosMemoryRepository implements core.MemoryRepository
var _ core.MemoryRepository = (*cosmosMemoryRepository)(nil)

// NewCosmosMemoryRepository creates a new Cosmos DB memory repository
func NewCosmosMemoryRepository(opts *ContainerOpts) (core.MemoryRepository, error) {
	if opts == nil {
		return nil, goerrors.New("cosmos options cannot be nil")
	}
	if opts.DatabaseID == "" {
		return nil, goerrors.New("database ID cannot be empty")
	}
	if opts.ContainerID == "" {
		return nil, goerrors.New("container ID cannot be empty")
	}

	container, err := NewCosmosContainerClient(opts)
	if err != nil {
		return nil, goerrors.Errorf("failed to create Cosmos container client: %w", err)
	}
	if container == nil {
		return nil, goerrors.New("cosmos container client cannot be nil")
	}

	return NewCosmosMemoryRepositoryFromContainerClient(container, opts.Obsv), nil
}

// NewCosmosMemoryRepositoryFromContainerClient creates a new Cosmos memory repository from an existing Cosmos container client.
func NewCosmosMemoryRepositoryFromContainerClient(client *azcosmos.ContainerClient, obsv observability.Exporters) core.MemoryRepository {
	return &cosmosMemoryRepository{
		container: client,
		obsv:      obsv,
	}
}

// memoryPartitionKeyString generates a partition key string for a memory based on repository ID
func memoryPartitionKeyString(repoID core.RepositoryID) string {
	return fmt.Sprintf("memory:repo:%v:v0", repoID)
}

// memoryPartitionKey generates a partition key for a memory based on repository ID
func memoryPartitionKey(repoID core.RepositoryID) azcosmos.PartitionKey {
	return azcosmos.NewPartitionKey().AppendString(memoryPartitionKeyString(repoID))
}

// memoryDocument represents the document structure stored in Cosmos DB
type memoryDocument struct {
	ID           string            `json:"id"`
	Subject      string            `json:"subject"`
	Fact         string            `json:"fact"`
	Citations    []string          `json:"citations"`
	Reason       string            `json:"reason"`
	Source       core.MemorySource `json:"source"`
	CreatedAt    time.Time         `json:"created_at"`
	PartitionKey string            `json:"partition_key"`
}

// fromDomain converts a core.Memory to a memoryDocument
func (doc *memoryDocument) fromDomain(repoID core.RepositoryID, memory *core.Memory) {
	doc.ID = string(memory.ID)
	doc.Subject = memory.Subject
	doc.Fact = memory.Fact
	doc.Citations = memory.Citations
	doc.Reason = memory.Reason
	doc.Source = memory.Source
	doc.CreatedAt = memory.CreatedAt
	doc.PartitionKey = memoryPartitionKeyString(repoID)
}

// toDomain converts a memoryDocument to a core.Memory
func (doc *memoryDocument) toDomain() *core.Memory {
	return &core.Memory{
		ID:        core.MemoryID(doc.ID),
		Subject:   doc.Subject,
		Fact:      doc.Fact,
		Citations: doc.Citations,
		Reason:    doc.Reason,
		Source:    doc.Source,
		CreatedAt: doc.CreatedAt,
	}
}

// Save stores a memory in the Cosmos DB repository
func (r *cosmosMemoryRepository) Save(ctx context.Context, repoID core.RepositoryID, memory *core.Memory) error {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.Save")
	startTime := time.Now()
	operation := "save"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()
	if memory == nil {
		r.recordCosmosError(operation, "nil_memory")
		return goerrors.New("memory cannot be nil")
	}

	// Set creation time if not already set
	if memory.CreatedAt.IsZero() {
		memory.CreatedAt = time.Now().UTC()
	}

	// Convert to document format
	doc := &memoryDocument{}
	doc.fromDomain(repoID, memory)

	pk := memoryPartitionKey(repoID)

	marshalled, err := json.Marshal(doc)
	if err != nil {
		r.recordCosmosError(operation, "marshal_failed")
		return goerrors.Errorf("failed to marshal memory: %w", err)
	}

	// Record payload size for capacity planning
	r.obsv.Statter.Distribution(metricCosmosPayloadSize, map[string]string{"operation": operation}, float64(len(marshalled)))

	_, err = r.container.UpsertItem(ctx, pk, marshalled, nil)
	if err != nil {
		r.recordCosmosErrorFromAzure(operation, err)
		return goerrors.Errorf("failed to save memory to cosmos: %w", err)
	}

	return nil
}

// FindByID retrieves a memory by its ID and repository NWO
func (r *cosmosMemoryRepository) FindByID(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) (*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.FindByID")
	startTime := time.Now()
	operation := "find_by_id"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()
	pk := memoryPartitionKey(repoID)

	response, err := r.container.ReadItem(ctx, pk, string(id), nil)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusNotFound {
			// Not found is expected, not an error to track
			return nil, core.ErrMemoryNotFound
		}
		r.recordCosmosErrorFromAzure(operation, err)
		return nil, goerrors.Errorf("failed to read memory from cosmos: %w", err)
	}

	var doc memoryDocument
	err = json.Unmarshal(response.Value, &doc)
	if err != nil {
		r.recordCosmosError(operation, "unmarshal_failed")
		return nil, goerrors.Errorf("failed to unmarshal memory document: %w", err)
	}

	return doc.toDomain(), nil
}

// FindByRepository retrieves all memories for a given repository NWO
func (r *cosmosMemoryRepository) FindByRepository(ctx context.Context, repoID core.RepositoryID) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.FindByRepository")
	startTime := time.Now()
	operation := "find_by_repository"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@partition_key", Value: memoryPartitionKeyString(repoID)},
		},
	}

	query := "SELECT * FROM c WHERE c.partition_key = @partition_key"
	pk := memoryPartitionKey(repoID)
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	memories, err := r.getAllMemoriesFromPager(ctx, pager, operation)
	if err != nil {
		// Error already recorded in getAllMemoriesFromPager with specific error type
		return nil, goerrors.Errorf("failed to get memories for repository: %w", err)
	}

	return memories, nil
}

// Delete removes a memory by its ID
func (r *cosmosMemoryRepository) Delete(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) error {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.Delete")
	startTime := time.Now()
	operation := "delete"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	// First, we need to find the memory to get the partition key
	partitionKey := memoryPartitionKey(repoID)
	_, err := r.container.DeleteItem(ctx, partitionKey, string(id), nil)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusNotFound {
			// Not found is expected, not an error to track
			return core.ErrMemoryNotFound
		}
		r.recordCosmosErrorFromAzure(operation, err)
		return goerrors.Errorf("failed to delete memory from cosmos: %w", err)
	}

	return nil
}

// FindRecentByRepository retrieves the most recent N memories for a given repository NWO
func (r *cosmosMemoryRepository) FindRecentByRepository(ctx context.Context, repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.FindRecentByRepository")
	startTime := time.Now()
	operation := "find_recent_by_repository"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	// If limit is 0 we can short circuit the actual Cosmos call
	if limit == 0 {
		return []*core.Memory{}, nil
	}

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@partition_key", Value: memoryPartitionKeyString(repoID)},
			{Name: "@limit", Value: limit},
		},
	}

	// Query with ORDER BY created_at DESC and OFFSET 0 LIMIT N
	query := "SELECT * FROM c WHERE c.partition_key = @partition_key ORDER BY c.created_at DESC OFFSET 0 LIMIT @limit"
	pk := memoryPartitionKey(repoID)
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	memories, err := r.getAllMemoriesFromPager(ctx, pager, operation)
	if err != nil {
		// Error already recorded in getAllMemoriesFromPager with specific error type
		return nil, goerrors.Errorf("failed to get recent memories for repository: %w", err)
	}

	return memories, nil
}

func (r *cosmosMemoryRepository) getAllMemoriesFromPager(ctx context.Context, pager *runtime.Pager[azcosmos.QueryItemsResponse], operation string) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.getAllMemoriesFromPager")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, "get_all_memories_from_pager", startTime)
		span.End()
	}()
	var memories []*core.Memory

	for pager.More() {
		response, err := pager.NextPage(ctx)
		if err != nil {
			r.recordCosmosErrorFromAzure(operation, err)
			return nil, err
		}

		for _, item := range response.Items {
			var doc memoryDocument
			err = json.Unmarshal(item, &doc)
			if err != nil {
				r.recordCosmosError(operation, "unmarshal_failed")
				return nil, goerrors.Errorf("failed to unmarshal memory document: %w", err)
			}
			memories = append(memories, doc.toDomain())
		}
	}

	return memories, nil
}

func (r *cosmosMemoryRepository) recordDuration(_ context.Context, operation string, startTime time.Time) {
	duration := time.Since(startTime)
	r.obsv.Statter.DistributionMs(metricCosmosOperationDuration, map[string]string{
		"operation": operation,
	}, duration)
}

// recordCosmosError records a Cosmos-specific error metric.
func (r *cosmosMemoryRepository) recordCosmosError(operation, errorType string) {
	r.obsv.Statter.Increment(metricCosmosErrorCount, map[string]string{
		"operation":  operation,
		"error_type": errorType,
	})
}

// recordCosmosErrorFromAzure extracts error details from Azure SDK errors and records them.
func (r *cosmosMemoryRepository) recordCosmosErrorFromAzure(operation string, err error) {
	errorType := "unknown"
	var responseErr *azcore.ResponseError
	if errors.As(err, &responseErr) {
		switch responseErr.StatusCode {
		case http.StatusTooManyRequests:
			errorType = "throttled"
		case http.StatusServiceUnavailable:
			errorType = "service_unavailable"
		case http.StatusRequestTimeout, http.StatusGatewayTimeout:
			errorType = "timeout"
		case http.StatusUnauthorized, http.StatusForbidden:
			errorType = "auth_failed"
		default:
			errorType = "azure_error"
		}
	}
	r.recordCosmosError(operation, errorType)
}

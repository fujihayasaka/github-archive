// Package cosmos provides a Cosmos DB implementation of the memory repository.
package cosmos

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
)

// cosmosMemoryRepository implements the core.MemoryRepository interface using Cosmos DB.

type cosmosMemoryRepository struct {
	container *azcosmos.ContainerClient
	obsv      observability.Exporters
}

// Ensure that cosmosMemoryRepository implements core.MemoryRepository
var _ core.MemoryRepository = (*cosmosMemoryRepository)(nil)

// NewCosmosMemoryRepository creates a new Cosmos DB memory repository
func NewCosmosMemoryRepository(opts *CosmosContainerOpts) (core.MemoryRepository, error) {
	if opts == nil {
		return nil, errors.New("cosmos options cannot be nil")
	}
	if opts.DatabaseID == "" {
		return nil, errors.New("database ID cannot be empty")
	}
	if opts.ContainerID == "" {
		return nil, errors.New("container ID cannot be empty")
	}

	container, err := NewCosmosContainerClient(opts)
	if err != nil {
		return nil, fmt.Errorf("failed to create Cosmos container client: %w", err)
	}
	if container == nil {
		return nil, errors.New("cosmos container client cannot be nil")
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

func (r *cosmosMemoryRepository) recordDuration(ctx context.Context, operation string, startTime time.Time) {
	duration := time.Since(startTime)
	r.obsv.Statter.Timing("cosmosMemoryRepository.operation", map[string]string{
		"operation": operation,
	}, duration)
}

// Save stores a memory in the Cosmos DB repository
func (r *cosmosMemoryRepository) Save(ctx context.Context, repoID core.RepositoryID, memory *core.Memory) error {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.Save")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, "save", startTime)
		span.End()
	}()
	if memory == nil {
		return errors.New("memory cannot be nil")
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
		return fmt.Errorf("failed to marshal memory: %w", err)
	}

	_, err = r.container.UpsertItem(ctx, pk, marshalled, nil)
	if err != nil {
		return fmt.Errorf("failed to save memory to cosmos: %w", err)
	}

	return nil
}

// FindByID retrieves a memory by its ID and repository NWO
func (r *cosmosMemoryRepository) FindByID(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) (*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.FindByID")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, "find_by_id", startTime)
		span.End()
	}()
	pk := memoryPartitionKey(repoID)

	response, err := r.container.ReadItem(ctx, pk, string(id), nil)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == 404 {
			return nil, core.ErrMemoryNotFound
		}
		return nil, fmt.Errorf("failed to read memory from cosmos: %w", err)
	}

	var doc memoryDocument
	err = json.Unmarshal(response.Value, &doc)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal memory document: %w", err)
	}

	return doc.toDomain(), nil
}

// FindByRepository retrieves all memories for a given repository NWO
func (r *cosmosMemoryRepository) FindByRepository(ctx context.Context, repoID core.RepositoryID) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.FindByRepository")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, "find_by_repository", startTime)
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

	memories, err := r.getAllMemoriesFromPager(ctx, pager)
	if err != nil {
		return nil, fmt.Errorf("failed to get memories for repository: %w", err)
	}

	return memories, nil
}

// Delete removes a memory by its ID
func (r *cosmosMemoryRepository) Delete(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) error {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.Delete")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, "delete", startTime)
		span.End()
	}()

	// First, we need to find the memory to get the partition key
	partitionKey := memoryPartitionKey(repoID)
	_, err := r.container.DeleteItem(ctx, partitionKey, string(id), nil)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == 404 {
			return core.ErrMemoryNotFound
		}
		return fmt.Errorf("failed to delete memory from cosmos: %w", err)
	}

	return nil
}

// getAllMemoriesFromPager retrieves all memory items from the pager and converts them to core.Memory
func (r *cosmosMemoryRepository) getAllMemoriesFromPager(ctx context.Context, pager *runtime.Pager[azcosmos.QueryItemsResponse]) ([]*core.Memory, error) {
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
			return nil, err
		}

		for _, item := range response.Items {
			var doc memoryDocument
			err = json.Unmarshal(item, &doc)
			if err != nil {
				return nil, fmt.Errorf("failed to unmarshal memory document: %w", err)
			}
			memories = append(memories, doc.toDomain())
		}
	}

	return memories, nil
}

// FindRecentByRepository retrieves the most recent N memories for a given repository NWO
func (r *cosmosMemoryRepository) FindRecentByRepository(ctx context.Context, repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryRepository.FindRecentByRepository")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, "find_recent_by_repository", startTime)
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

	memories, err := r.getAllMemoriesFromPager(ctx, pager)
	if err != nil {
		return nil, fmt.Errorf("failed to get recent memories for repository: %w", err)
	}

	return memories, nil
}

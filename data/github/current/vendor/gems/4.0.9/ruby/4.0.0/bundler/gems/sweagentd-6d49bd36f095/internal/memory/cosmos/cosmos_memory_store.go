// Package cosmos provides a Cosmos DB implementation of the memory store.
package cosmos

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
)

// Telemetry metric names for Cosmos store operations.
const (
	metricCosmosOperationDuration = "memory_cosmos.operation_duration"
	metricCosmosErrorCount        = "memory_cosmos.error_count"
	metricCosmosPayloadSize       = "memory_cosmos.payload_size"
	metricCosmosRequestCharge     = "memory_cosmos.request_charge"
	metricCosmosReturnedItemCount = "memory_cosmos.returned_item_count"
	metricCosmosBatchPayloadSize  = "memory_cosmos.batch_payload_size"
)

// cosmosMemoryStore implements the core.MemoryStore interface using Cosmos DB.

type cosmosMemoryStore struct {
	container *azcosmos.ContainerClient
	obsv      observability.Exporters
}

// Ensure that cosmosMemoryStore implements core.MemoryStore
var _ core.MemoryStore = (*cosmosMemoryStore)(nil)

// NewCosmosMemoryStore creates a new Cosmos DB memory store
func NewCosmosMemoryStore(opts *ContainerOpts) (core.MemoryStore, error) {
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

	return NewCosmosMemoryStoreFromContainerClient(container, opts.Obsv), nil
}

// NewCosmosMemoryStoreFromContainerClient creates a new Cosmos memory store from an existing Cosmos container client.
func NewCosmosMemoryStoreFromContainerClient(client *azcosmos.ContainerClient, obsv observability.Exporters) core.MemoryStore {
	return &cosmosMemoryStore{
		container: client,
		obsv:      obsv,
	}
}

// repoPartitionKeyString generates a Cosmos DB partition key string for a repository.
func repoPartitionKeyString(repoID core.RepositoryID) string {
	return fmt.Sprintf("memory:repo:%d:v0", repoID)
}

// userPartitionKeyString generates a Cosmos DB partition key string for a user.
func userPartitionKeyString(userID uint64) string {
	return fmt.Sprintf("memory:user:%d:v0", userID)
}

func scopeFromPartitionKey(pkStr string) core.MemoryScope {
	switch {
	case strings.HasPrefix(pkStr, "memory:repo:"):
		return core.MemoryScopeRepository
	case strings.HasPrefix(pkStr, "memory:user:"):
		return core.MemoryScopeUser
	default:
		return ""
	}
}

// partitionKeyFromString generates an azcosmos partition key from a string.
func partitionKeyFromString(pkStr string) azcosmos.PartitionKey {
	return azcosmos.NewPartitionKey().AppendString(pkStr)
}

// memoryDocument represents the document structure stored in Cosmos DB
type memoryDocument struct {
	ID                    string            `json:"id"`
	Subject               string            `json:"subject"`
	Fact                  string            `json:"fact"`
	Citations             []string          `json:"citations"`
	Reason                string            `json:"reason"`
	Source                core.MemorySource `json:"source"`
	Scope                 core.MemoryScope  `json:"scope"`
	CreatedAt             time.Time         `json:"created_at"`
	UpdatedAt             time.Time         `json:"updated_at"`
	ExpiresAt             time.Time         `json:"expires_at"`
	Votes                 []core.Vote       `json:"votes"`
	BillingOrganizationID uint64            `json:"billing_organization_id"`
	BillingEnterpriseID   uint64            `json:"billing_enterprise_id"`
	TTL                   int64             `json:"ttl"`
	PartitionKey          string            `json:"partition_key"`
	ETag                  *azcore.ETag      `json:"_etag,omitempty"`
}

// fromDomain converts a core.Memory to a memoryDocument.
// now is used to compute the Cosmos TTL consistently with the caller's clock.
func (doc *memoryDocument) fromDomain(pkStr string, memory *core.Memory, now time.Time) {
	doc.ID = string(memory.ID)
	doc.Subject = memory.Subject
	doc.Fact = memory.Fact
	doc.Citations = memory.Citations
	doc.Reason = memory.Reason
	doc.Source = memory.Source
	doc.Scope = memory.Scope
	if doc.Scope == "" {
		doc.Scope = scopeFromPartitionKey(pkStr)
	}
	doc.CreatedAt = memory.CreatedAt
	doc.UpdatedAt = memory.UpdatedAt
	doc.ExpiresAt = memory.ExpiresAt
	doc.Votes = memory.Votes
	doc.BillingOrganizationID = memory.BillingOrganizationID
	doc.BillingEnterpriseID = memory.BillingEnterpriseID
	doc.PartitionKey = pkStr

	// Compute TTL for Cosmos: seconds from now until expiry.
	// Clamp to 1 because CosmosDB requires a positive non-zero integer for TTL;
	// a negative value would disable expiration.
	doc.TTL = max(int64(memory.ExpiresAt.Sub(now).Seconds()), 1)
}

// toDomain converts a memoryDocument to a core.Memory
func (doc *memoryDocument) toDomain() *core.Memory {
	scope := doc.Scope
	if scope == "" {
		scope = scopeFromPartitionKey(doc.PartitionKey)
	}
	m := &core.Memory{
		ID:                    core.MemoryID(doc.ID),
		Subject:               doc.Subject,
		Fact:                  doc.Fact,
		Citations:             doc.Citations,
		Reason:                doc.Reason,
		Source:                doc.Source,
		Scope:                 scope,
		CreatedAt:             doc.CreatedAt,
		UpdatedAt:             doc.UpdatedAt,
		ExpiresAt:             doc.ExpiresAt,
		Votes:                 doc.Votes,
		BillingOrganizationID: doc.BillingOrganizationID,
		BillingEnterpriseID:   doc.BillingEnterpriseID,
	}
	if doc.ETag != nil {
		m.ETag = string(*doc.ETag)
	}
	// Backward compatibility: add initial upvote for legacy documents without voting fields.
	// Populate VoteSource from the memory's Source so downstream logic has full provenance.
	if len(m.Votes) == 0 {
		m.Votes = []core.Vote{{
			Direction: core.UpVote,
			Timestamp: m.CreatedAt,
			Source: core.VoteSource{
				Agent:     m.Source.Agent,
				RepoNWO:   m.Source.NWO,
				CommitSHA: m.Source.CommitSHA,
				BaseModel: m.Source.BaseModel,
				UserID:    m.Source.User.ID,
				UserLogin: m.Source.User.Login,
				Reason:    m.Reason,
			},
		}}
	}
	if m.UpdatedAt.IsZero() {
		m.UpdatedAt = m.CreatedAt
	}
	if m.ExpiresAt.IsZero() {
		m.ExpiresAt = m.CreatedAt.Add(core.VoteWindow)
	}
	return m
}

// SaveForRepository stores a memory scoped to a repository.
func (r *cosmosMemoryStore) SaveForRepository(ctx context.Context, repoID core.RepositoryID, memory *core.Memory) error {
	return r.save(ctx, repoPartitionKeyString(repoID), memory)
}

// SaveBatchForRepository atomically saves multiple memories scoped to a repository
// using a Cosmos DB transactional batch. All saves succeed or all fail together.
func (r *cosmosMemoryStore) SaveBatchForRepository(ctx context.Context, repoID core.RepositoryID, memories []*core.Memory) error {
	return r.saveBatch(ctx, repoPartitionKeyString(repoID), memories)
}

// FindByRepository retrieves all memories for a given repository.
func (r *cosmosMemoryStore) FindByRepository(ctx context.Context, repoID core.RepositoryID) ([]*core.Memory, error) {
	return r.findByPartition(ctx, repoPartitionKeyString(repoID), "find_by_repository")
}

// FindByFactForRepository retrieves memories matching the given fact text within a repository scope.
func (r *cosmosMemoryStore) FindByFactForRepository(ctx context.Context, repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
	return r.findByFact(ctx, repoPartitionKeyString(repoID), fact, "find_by_fact_for_repository")
}

// FindRecentByRepository retrieves the most recent N memories for a given repository.
func (r *cosmosMemoryStore) FindRecentByRepository(ctx context.Context, repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
	return r.findRecentByPartition(ctx, repoPartitionKeyString(repoID), limit, "find_recent_by_repository")
}

// DeleteForRepository removes a memory by its ID within a repository scope.
func (r *cosmosMemoryStore) DeleteForRepository(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) error {
	return r.deleteOne(ctx, repoPartitionKeyString(repoID), id)
}

// DeleteBatchForRepository removes specific memories by their IDs within a repository scope.
func (r *cosmosMemoryStore) DeleteBatchForRepository(ctx context.Context, repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
	return r.deleteBatch(ctx, repoPartitionKeyString(repoID), ids)
}

// DeleteAllForRepository removes all memories for a given repository.
func (r *cosmosMemoryStore) DeleteAllForRepository(ctx context.Context, repoID core.RepositoryID) error {
	return r.deleteAll(ctx, repoPartitionKeyString(repoID))
}

// CountByRepository returns the total number of memories stored for a given repository.
func (r *cosmosMemoryStore) CountByRepository(ctx context.Context, repoID core.RepositoryID) (int, error) {
	return r.countByPartition(ctx, repoPartitionKeyString(repoID), "count_by_repository")
}

// CountByUser returns the total number of memories stored for a given user.
func (r *cosmosMemoryStore) CountByUser(ctx context.Context, userID uint64, billingFilter *core.BillingEntity) (int, error) {
	if billingFilter != nil {
		return r.countByPartitionWithBilling(ctx, userPartitionKeyString(userID), *billingFilter, "count_by_user_with_billing")
	}
	return r.countByPartition(ctx, userPartitionKeyString(userID), "count_by_user")
}

// SaveForUser stores a memory scoped to a user.
func (r *cosmosMemoryStore) SaveForUser(ctx context.Context, userID uint64, memory *core.Memory) error {
	return r.save(ctx, userPartitionKeyString(userID), memory)
}

// SaveBatchForUser atomically saves multiple memories scoped to a user
// using a Cosmos DB transactional batch. All saves succeed or all fail together.
func (r *cosmosMemoryStore) SaveBatchForUser(ctx context.Context, userID uint64, memories []*core.Memory) error {
	return r.saveBatch(ctx, userPartitionKeyString(userID), memories)
}

// FindByUser retrieves all memories for a given user.
func (r *cosmosMemoryStore) FindByUser(ctx context.Context, userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
	if billingFilter != nil {
		return r.findByPartitionWithBilling(ctx, userPartitionKeyString(userID), *billingFilter, "find_by_user_with_billing")
	}
	return r.findByPartition(ctx, userPartitionKeyString(userID), "find_by_user")
}

// FindByFactForUser retrieves memories matching the given fact text within a user scope.
func (r *cosmosMemoryStore) FindByFactForUser(ctx context.Context, userID uint64, fact string) ([]*core.Memory, error) {
	return r.findByFact(ctx, userPartitionKeyString(userID), fact, "find_by_fact_for_user")
}

// FindRecentByUser retrieves the most recent N memories for a given user.
func (r *cosmosMemoryStore) FindRecentByUser(ctx context.Context, userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
	if billingFilter != nil {
		return r.findRecentByPartitionWithBilling(ctx, userPartitionKeyString(userID), limit, *billingFilter, "find_recent_by_user_with_billing")
	}
	return r.findRecentByPartition(ctx, userPartitionKeyString(userID), limit, "find_recent_by_user")
}

// ListBillingEntityMemories retrieves one page of user-scoped memories for a billing entity.
func (r *cosmosMemoryStore) ListBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.ListBillingEntityMemories")
	startTime := time.Now()
	operation := "list_billing_entity_memories"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	if pageRequest.Limit == 0 {
		return &core.MemoryPage{}, nil
	}
	if filter.IsZero() {
		return nil, core.ErrInvalidBillingFilter
	}
	if filter.UserID == 0 {
		return nil, core.ErrInvalidUserFilter
	}
	if pageRequest.SnapshotTime.IsZero() {
		return nil, core.ErrInvalidSnapshotTime
	}

	pkStr := userPartitionKeyString(filter.UserID)
	params := []azcosmos.QueryParameter{
		{Name: "@snapshot_time", Value: pageRequest.SnapshotTime.UTC().Format(time.RFC3339Nano)},
		{Name: "@partition_key", Value: pkStr},
	}
	// Cosmos stores memory timestamps as JSON strings encoded from Go time.Time.
	// RFC3339Nano fractional precision is not a perfect fixed-width lexical
	// timestamp, so this cutoff is a best-effort bound to keep exports finite,
	// not a point-in-time snapshot guarantee. Minor same-second drift is OK.
	query := "SELECT * FROM c WHERE c.created_at <= @snapshot_time AND c.partition_key = @partition_key"
	pk := partitionKeyFromString(pkStr)
	if filter.OrganizationID != 0 {
		params = append(params, azcosmos.QueryParameter{Name: "@billing_org_id", Value: filter.OrganizationID})
		query += " AND c.billing_organization_id = @billing_org_id"
	}
	if filter.EnterpriseID != 0 {
		params = append(params, azcosmos.QueryParameter{Name: "@billing_enterprise_id", Value: filter.EnterpriseID})
		query += " AND c.billing_enterprise_id = @billing_enterprise_id"
	}

	opt := azcosmos.QueryOptions{
		QueryParameters: params,
		PageSizeHint:    int32(pageRequest.Limit),
	}
	if pageRequest.ContinuationToken != "" {
		opt.ContinuationToken = &pageRequest.ContinuationToken
	}

	pager := r.container.NewQueryItemsPager(query, pk, &opt)
	if !pager.More() {
		return &core.MemoryPage{}, nil
	}

	response, err := pager.NextPage(ctx)
	if err != nil {
		r.recordCosmosErrorFromAzure(ctx, operation, err)
		if isCosmosThrottled(err) {
			return nil, core.ErrMemoryStoreThrottled
		}
		if pageRequest.ContinuationToken != "" && isCosmosBadRequest(err) {
			return nil, core.ErrInvalidContinuation
		}
		return nil, goerrors.Errorf("failed to query billing entity memories: %w", err)
	}
	r.recordQueryResponseMetrics(ctx, operation, response)

	memories := make([]*core.Memory, 0, len(response.Items))
	for _, item := range response.Items {
		var doc memoryDocument
		err = json.Unmarshal(item, &doc)
		if err != nil {
			r.recordCosmosError(ctx, operation, "unmarshal_failed")
			return nil, goerrors.Errorf("failed to unmarshal memory document: %w", err)
		}
		memories = append(memories, doc.toDomain())
	}

	nextToken := ""
	if response.ContinuationToken != nil {
		nextToken = *response.ContinuationToken
	}

	return &core.MemoryPage{
		Memories:          memories,
		ContinuationToken: nextToken,
	}, nil
}

// DeleteForUser removes a memory by its ID within a user scope.
func (r *cosmosMemoryStore) DeleteForUser(ctx context.Context, userID uint64, id core.MemoryID) error {
	return r.deleteOne(ctx, userPartitionKeyString(userID), id)
}

// DeleteBatchForUser removes specific memories by their IDs within a user scope.
func (r *cosmosMemoryStore) DeleteBatchForUser(ctx context.Context, userID uint64, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
	return r.deleteBatch(ctx, userPartitionKeyString(userID), ids)
}

// DeleteAllForUser removes all memories for a given user.
func (r *cosmosMemoryStore) DeleteAllForUser(ctx context.Context, userID uint64) error {
	return r.deleteAll(ctx, userPartitionKeyString(userID))
}

// DeleteBillingEntityMemories deletes one bounded page of user-scoped memories
// for a billing entity. It queries matching document IDs using the same filters
// as ListBillingEntityMemories, then deletes them via transactional batches.
func (r *cosmosMemoryStore) DeleteBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.DeleteBillingEntityMemories")
	startTime := time.Now()
	operation := "delete_billing_entity_memories"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	if pageRequest.Limit == 0 {
		return &core.BillingEntityDeleteResult{}, nil
	}
	if filter.IsZero() {
		return nil, core.ErrInvalidBillingFilter
	}
	if filter.UserID == 0 {
		return nil, core.ErrInvalidUserFilter
	}
	if pageRequest.SnapshotTime.IsZero() {
		return nil, core.ErrInvalidSnapshotTime
	}

	// Query only document IDs (not full documents) matching the billing entity filters.
	pkStr := userPartitionKeyString(filter.UserID)
	params := []azcosmos.QueryParameter{
		{Name: "@snapshot_time", Value: pageRequest.SnapshotTime.UTC().Format(time.RFC3339Nano)},
		{Name: "@partition_key", Value: pkStr},
	}
	query := "SELECT VALUE c.id FROM c WHERE c.created_at <= @snapshot_time AND c.partition_key = @partition_key"
	pk := partitionKeyFromString(pkStr)
	if filter.OrganizationID != 0 {
		params = append(params, azcosmos.QueryParameter{Name: "@billing_org_id", Value: filter.OrganizationID})
		query += " AND c.billing_organization_id = @billing_org_id"
	}
	if filter.EnterpriseID != 0 {
		params = append(params, azcosmos.QueryParameter{Name: "@billing_enterprise_id", Value: filter.EnterpriseID})
		query += " AND c.billing_enterprise_id = @billing_enterprise_id"
	}

	opt := azcosmos.QueryOptions{
		QueryParameters: params,
		PageSizeHint:    int32(pageRequest.Limit),
	}
	if pageRequest.ContinuationToken != "" {
		opt.ContinuationToken = &pageRequest.ContinuationToken
	}

	// Fetch one page of matching document IDs.
	pager := r.container.NewQueryItemsPager(query, pk, &opt)
	if !pager.More() {
		return &core.BillingEntityDeleteResult{}, nil
	}

	response, err := pager.NextPage(ctx)
	if err != nil {
		r.recordCosmosErrorFromAzure(ctx, operation, err)
		if isCosmosThrottled(err) {
			return nil, core.ErrMemoryStoreThrottled
		}
		if pageRequest.ContinuationToken != "" && isCosmosBadRequest(err) {
			return nil, core.ErrInvalidContinuation
		}
		return nil, goerrors.Errorf("failed to query billing entity memories for delete: %w", err)
	}
	r.recordQueryResponseMetrics(ctx, operation, response)

	// Extract the IDs from the query response.
	var ids []string
	for _, item := range response.Items {
		var id string
		err = json.Unmarshal(item, &id)
		if err != nil {
			r.recordCosmosError(ctx, operation, "unmarshal_failed")
			return nil, goerrors.Errorf("failed to unmarshal memory ID: %w", err)
		}
		ids = append(ids, id)
	}

	// Delete the queried IDs in transactional batches.
	totalDeleted := 0
	for i := 0; i < len(ids); i += cosmosTransactionalBatchMaxSize {
		end := min(i+cosmosTransactionalBatchMaxSize, len(ids))
		chunk := ids[i:end]
		err := r.deleteIDBatch(ctx, pk, chunk, operation, totalDeleted)
		if err != nil {
			return nil, err
		}
		totalDeleted += len(chunk)
	}

	nextToken := ""
	if response.ContinuationToken != nil {
		nextToken = *response.ContinuationToken
	}

	return &core.BillingEntityDeleteResult{
		DeletedCount:      uint(totalDeleted),
		ContinuationToken: nextToken,
	}, nil
}

// save stores a memory document in CosmosDB under the specified partition key.
func (r *cosmosMemoryStore) save(ctx context.Context, pkStr string, memory *core.Memory) error {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.Save")
	startTime := time.Now()
	operation := "save"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()
	if memory == nil {
		r.recordCosmosError(ctx, operation, "nil_memory")
		return goerrors.New("memory cannot be nil")
	}

	// Set default timestamps if not already set
	now := time.Now().UTC()
	if memory.CreatedAt.IsZero() {
		memory.CreatedAt = now
	}
	if memory.UpdatedAt.IsZero() {
		memory.UpdatedAt = now
	}
	if memory.ExpiresAt.IsZero() {
		memory.ExpiresAt = now.Add(core.VoteWindow)
	}

	// Convert to document format
	doc := &memoryDocument{}
	doc.fromDomain(pkStr, memory, now)

	pk := partitionKeyFromString(pkStr)

	marshalled, err := json.Marshal(doc)
	if err != nil {
		r.recordCosmosError(ctx, operation, "marshal_failed")
		return goerrors.Errorf("failed to marshal memory: %w", err)
	}

	// Record payload size for capacity planning
	r.obsv.Distribution(ctx, metricCosmosPayloadSize, map[string]string{"operation": operation}, float64(len(marshalled)))

	// Use optimistic concurrency when an ETag is present
	var opts *azcosmos.ItemOptions
	if memory.ETag != "" {
		etag := azcore.ETag(memory.ETag)
		opts = &azcosmos.ItemOptions{IfMatchEtag: &etag}
	}

	_, err = r.container.UpsertItem(ctx, pk, marshalled, opts)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusPreconditionFailed {
			return core.ErrConcurrencyConflict
		}
		r.recordCosmosErrorFromAzure(ctx, operation, err)
		return goerrors.Errorf("failed to save memory to cosmos: %w", err)
	}

	return nil
}

// saveBatch saves multiple memory documents in CosmosDB using transactional
// batches. Operations are chunked by cosmosTransactionalBatchMaxSize (100) to
// respect the Cosmos DB limit. Each chunk is atomic (all-or-nothing).
func (r *cosmosMemoryStore) saveBatch(ctx context.Context, pkStr string, memories []*core.Memory) error {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.SaveBatch")
	startTime := time.Now()
	operation := "save_batch"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	if len(memories) == 0 {
		return nil
	}

	now := time.Now().UTC()
	pk := partitionKeyFromString(pkStr)

	for i := 0; i < len(memories); i += cosmosTransactionalBatchMaxSize {
		end := min(i+cosmosTransactionalBatchMaxSize, len(memories))
		chunk := memories[i:end]

		batch := r.container.NewTransactionalBatch(pk)
		var batchPayloadSize int

		for _, memory := range chunk {
			if memory == nil {
				r.recordCosmosError(ctx, operation, "nil_memory")
				return goerrors.New("memory cannot be nil")
			}

			if memory.CreatedAt.IsZero() {
				memory.CreatedAt = now
			}
			if memory.UpdatedAt.IsZero() {
				memory.UpdatedAt = now
			}
			if memory.ExpiresAt.IsZero() {
				memory.ExpiresAt = now.Add(core.VoteWindow)
			}

			doc := &memoryDocument{}
			doc.fromDomain(pkStr, memory, now)

			marshalled, err := json.Marshal(doc)
			if err != nil {
				r.recordCosmosError(ctx, operation, "marshal_failed")
				return goerrors.Errorf("failed to marshal memory: %w", err)
			}

			r.obsv.Distribution(ctx, metricCosmosPayloadSize, map[string]string{"operation": operation}, float64(len(marshalled)))
			batchPayloadSize += len(marshalled)

			var opts *azcosmos.TransactionalBatchItemOptions
			if memory.ETag != "" {
				etag := azcore.ETag(memory.ETag)
				opts = &azcosmos.TransactionalBatchItemOptions{IfMatchETag: &etag}
			}

			batch.UpsertItem(marshalled, opts)
		}

		r.obsv.Distribution(ctx, metricCosmosBatchPayloadSize, map[string]string{"operation": operation}, float64(batchPayloadSize))

		batchResp, err := r.container.ExecuteTransactionalBatch(ctx, batch, nil)
		if err != nil {
			r.recordCosmosErrorFromAzure(ctx, operation, err)
			return goerrors.Errorf("failed to execute transactional batch save: %w", err)
		}
		if !batchResp.Success {
			for _, result := range batchResp.OperationResults {
				if result.StatusCode == http.StatusPreconditionFailed {
					return core.ErrConcurrencyConflict
				}
			}
			r.recordCosmosError(ctx, operation, "batch_failure")
			var errs []error
			for _, result := range batchResp.OperationResults {
				errs = append(errs, goerrors.Errorf("batch save operation returned status %d", result.StatusCode))
			}
			return goerrors.Errorf("transactional batch save failed: %w", errors.Join(errs...))
		}
	}

	return nil
}

// countByPartition returns the total number of documents for a given partition key.
func (r *cosmosMemoryStore) countByPartition(ctx context.Context, pkStr, operation string) (int, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.countByPartition")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@partition_key", Value: pkStr},
		},
	}

	query := "SELECT VALUE COUNT(1) FROM c WHERE c.partition_key = @partition_key"
	pk := partitionKeyFromString(pkStr)
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	var count int
	for pager.More() {
		response, err := pager.NextPage(ctx)
		if err != nil {
			r.recordCosmosErrorFromAzure(ctx, operation, err)
			return 0, goerrors.Errorf("failed to count memories for partition: %w", err)
		}
		for _, item := range response.Items {
			var c int
			unmarshalErr := json.Unmarshal(item, &c)
			if unmarshalErr != nil {
				r.recordCosmosError(ctx, operation, "unmarshal_failed")
				return 0, goerrors.Errorf("failed to unmarshal count result: %w", unmarshalErr)
			}
			count += c
		}
	}

	return count, nil
}

// findByPartition retrieves all memories stored under the provided partition key.
func (r *cosmosMemoryStore) findByPartition(ctx context.Context, pkStr, operation string) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.findByPartition")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@partition_key", Value: pkStr},
		},
	}

	query := "SELECT * FROM c WHERE c.partition_key = @partition_key"
	pk := partitionKeyFromString(pkStr)
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	memories, err := r.getAllMemoriesFromPager(ctx, pager, operation)
	if err != nil {
		// Error already recorded in getAllMemoriesFromPager with specific error type
		return nil, goerrors.Errorf("failed to get memories for partition: %w", err)
	}

	return memories, nil
}

// findByFact retrieves memories matching the given fact text using a Cosmos DB query.
func (r *cosmosMemoryStore) findByFact(ctx context.Context, pkStr, fact, operation string) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.findByFact")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@partition_key", Value: pkStr},
			{Name: "@fact", Value: fact},
		},
	}

	query := "SELECT TOP 20 * FROM c WHERE c.partition_key = @partition_key AND c.fact = @fact ORDER BY c.updated_at DESC"
	pk := partitionKeyFromString(pkStr)
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	memories, err := r.getAllMemoriesFromPager(ctx, pager, operation)
	if err != nil {
		return nil, goerrors.Errorf("failed to find memory by fact: %w", err)
	}
	if len(memories) == 0 {
		return nil, nil
	}

	return memories, nil
}

// deleteOne removes a memory by its ID.
func (r *cosmosMemoryStore) deleteOne(ctx context.Context, pkStr string, id core.MemoryID) error {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.deleteOne")
	startTime := time.Now()
	operation := "delete"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	pk := partitionKeyFromString(pkStr)
	_, err := r.container.DeleteItem(ctx, pk, string(id), nil)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusNotFound {
			// Not found is expected, not an error to track
			return core.ErrMemoryNotFound
		}
		r.recordCosmosErrorFromAzure(ctx, operation, err)
		return goerrors.Errorf("failed to delete memory from cosmos: %w", err)
	}

	return nil
}

// DeleteBatch removes specific memories by their IDs.
// Items that are already deleted (HTTP 404) are silently ignored, since the
// caller's intent — "these items should not exist" — is already satisfied.
// Returns an error on the first non-404 failure encountered.
func (r *cosmosMemoryStore) deleteBatch(ctx context.Context, pkStr string, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.DeleteBatch")
	startTime := time.Now()
	operation := "delete_batch"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	result := &core.BatchDeleteResult{}

	if len(ids) == 0 {
		return result, nil
	}

	pk := partitionKeyFromString(pkStr)

	// Delete in batches of cosmosTransactionalBatchMaxSize.
	for i := 0; i < len(ids); i += cosmosTransactionalBatchMaxSize {
		end := min(i+cosmosTransactionalBatchMaxSize, len(ids))
		chunk := ids[i:end]

		batch := r.container.NewTransactionalBatch(pk)
		for _, id := range chunk {
			batch.DeleteItem(string(id), nil)
		}

		batchResp, err := r.container.ExecuteTransactionalBatch(ctx, batch, nil)
		if err != nil {
			r.recordCosmosErrorFromAzure(ctx, operation, err)
			result.Failed = append(result.Failed, chunk...)
			return result, goerrors.Errorf("failed to execute transactional batch delete: %w", err)
		}
		if !batchResp.Success {
			r.recordCosmosError(ctx, operation, "batch_partial_failure")
			result.Failed = append(result.Failed, chunk...)
			return result, goerrors.Errorf("transactional batch delete returned unsuccessful status")
		}

		result.Deleted = append(result.Deleted, chunk...)
	}

	return result, nil
}

// cosmosTransactionalBatchMaxSize is the maximum number of operations in a single
// Cosmos DB transactional batch. Cosmos DB enforces a limit of 100 operations per batch.
const cosmosTransactionalBatchMaxSize = 100

// deleteAll removes all memories for a given partition using transactional batches.
// It queries for document IDs page-by-page and deletes them in batches of up to 100
// (the Cosmos DB transactional batch limit) as each page is received, avoiding
// buffering all IDs in memory.
func (r *cosmosMemoryStore) deleteAll(ctx context.Context, pkStr string) error {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.deleteAll")
	startTime := time.Now()
	operation := "delete_all"
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	pk := partitionKeyFromString(pkStr)

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@partition_key", Value: pkStr},
		},
	}
	query := "SELECT VALUE c.id FROM c WHERE c.partition_key = @partition_key"
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	var pendingIDs []string
	totalDeleted := 0

	for pager.More() {
		response, err := pager.NextPage(ctx)
		if err != nil {
			r.recordCosmosErrorFromAzure(ctx, operation, err)
			return goerrors.Errorf("failed to query memory IDs for bulk delete: %w", err)
		}

		for _, item := range response.Items {
			var id string
			err = json.Unmarshal(item, &id)
			if err != nil {
				r.recordCosmosError(ctx, operation, "unmarshal_failed")
				return goerrors.Errorf("failed to unmarshal memory ID: %w", err)
			}
			pendingIDs = append(pendingIDs, id)

			if len(pendingIDs) >= cosmosTransactionalBatchMaxSize {
				err = r.deleteIDBatch(ctx, pk, pendingIDs, operation, totalDeleted)
				if err != nil {
					return err
				}
				totalDeleted += len(pendingIDs)
				pendingIDs = pendingIDs[:0]
			}
		}
	}

	// Flush remaining IDs.
	if len(pendingIDs) > 0 {
		err := r.deleteIDBatch(ctx, pk, pendingIDs, operation, totalDeleted)
		if err != nil {
			return err
		}
	}

	return nil
}

// findRecentByPartition retrieves the most recent N memories for a given partition key.
func (r *cosmosMemoryStore) findRecentByPartition(ctx context.Context, pkStr string, limit uint, operation string) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.findRecentByPartition")
	startTime := time.Now()
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
			{Name: "@partition_key", Value: pkStr},
			{Name: "@limit", Value: limit},
		},
	}

	// Query with ORDER BY created_at DESC and OFFSET 0 LIMIT N
	query := "SELECT * FROM c WHERE c.partition_key = @partition_key ORDER BY c.created_at DESC OFFSET 0 LIMIT @limit"
	pk := partitionKeyFromString(pkStr)
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	memories, err := r.getAllMemoriesFromPager(ctx, pager, operation)
	if err != nil {
		// Error already recorded in getAllMemoriesFromPager with specific error type
		return nil, goerrors.Errorf("failed to get recent memories for partition: %w", err)
	}

	return memories, nil
}

// billingWhereClause returns a Cosmos SQL WHERE fragment for billing entity filtering.
func billingWhereClause(filter core.BillingEntity) string {
	return " AND c.billing_organization_id = @billing_org_id AND c.billing_enterprise_id = @billing_enterprise_id"
}

// billingQueryParams returns the Cosmos query parameters for billing entity filtering.
func billingQueryParams(filter core.BillingEntity) []azcosmos.QueryParameter {
	return []azcosmos.QueryParameter{
		{Name: "@billing_org_id", Value: filter.OrganizationID},
		{Name: "@billing_enterprise_id", Value: filter.EnterpriseID},
	}
}

// findByPartitionWithBilling retrieves all memories under a partition key filtered by billing entity.
func (r *cosmosMemoryStore) findByPartitionWithBilling(ctx context.Context, pkStr string, filter core.BillingEntity, operation string) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.findByPartitionWithBilling")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	params := []azcosmos.QueryParameter{
		{Name: "@partition_key", Value: pkStr},
	}
	params = append(params, billingQueryParams(filter)...)

	opt := azcosmos.QueryOptions{QueryParameters: params}
	query := "SELECT * FROM c WHERE c.partition_key = @partition_key" + billingWhereClause(filter)
	pk := partitionKeyFromString(pkStr)
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	memories, err := r.getAllMemoriesFromPager(ctx, pager, operation)
	if err != nil {
		return nil, goerrors.Errorf("failed to get memories for partition with billing filter: %w", err)
	}

	return memories, nil
}

// findRecentByPartitionWithBilling retrieves the most recent N memories under a partition key filtered by billing entity.
func (r *cosmosMemoryStore) findRecentByPartitionWithBilling(ctx context.Context, pkStr string, limit uint, filter core.BillingEntity, operation string) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.findRecentByPartitionWithBilling")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	if limit == 0 {
		return []*core.Memory{}, nil
	}

	params := []azcosmos.QueryParameter{
		{Name: "@partition_key", Value: pkStr},
		{Name: "@limit", Value: limit},
	}
	params = append(params, billingQueryParams(filter)...)

	opt := azcosmos.QueryOptions{QueryParameters: params}
	query := "SELECT * FROM c WHERE c.partition_key = @partition_key" + billingWhereClause(filter) + " ORDER BY c.created_at DESC OFFSET 0 LIMIT @limit"
	pk := partitionKeyFromString(pkStr)
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	memories, err := r.getAllMemoriesFromPager(ctx, pager, operation)
	if err != nil {
		return nil, goerrors.Errorf("failed to get recent memories for partition with billing filter: %w", err)
	}

	return memories, nil
}

// countByPartitionWithBilling counts memories under a partition key filtered by billing entity.
func (r *cosmosMemoryStore) countByPartitionWithBilling(ctx context.Context, pkStr string, filter core.BillingEntity, operation string) (int, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.countByPartitionWithBilling")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	params := []azcosmos.QueryParameter{
		{Name: "@partition_key", Value: pkStr},
	}
	params = append(params, billingQueryParams(filter)...)

	opt := azcosmos.QueryOptions{QueryParameters: params}
	query := "SELECT VALUE COUNT(1) FROM c WHERE c.partition_key = @partition_key" + billingWhereClause(filter)
	pk := partitionKeyFromString(pkStr)
	pager := r.container.NewQueryItemsPager(query, pk, &opt)

	var count int
	for pager.More() {
		resp, err := pager.NextPage(ctx)
		if err != nil {
			r.recordCosmosErrorFromAzure(ctx, operation, err)
			return 0, goerrors.Errorf("failed to count memories with billing filter: %w", err)
		}
		for _, item := range resp.Items {
			var c int
			unmarshalErr := json.Unmarshal(item, &c)
			if unmarshalErr != nil {
				r.recordCosmosError(ctx, operation, "unmarshal_failed")
				return 0, goerrors.Errorf("failed to unmarshal count: %w", unmarshalErr)
			}
			count += c
		}
	}

	return count, nil
}

func (r *cosmosMemoryStore) getAllMemoriesFromPager(ctx context.Context, pager *runtime.Pager[azcosmos.QueryItemsResponse], operation string) ([]*core.Memory, error) {
	ctx, span := r.obsv.Tracer.Start(ctx, "cosmosMemoryStore.getAllMemoriesFromPager")
	startTime := time.Now()
	defer func() {
		r.recordDuration(ctx, "get_all_memories_from_pager", startTime)
		span.End()
	}()
	var memories []*core.Memory

	for pager.More() {
		response, err := pager.NextPage(ctx)
		if err != nil {
			r.recordCosmosErrorFromAzure(ctx, operation, err)
			return nil, err
		}

		for _, item := range response.Items {
			var doc memoryDocument
			err = json.Unmarshal(item, &doc)
			if err != nil {
				r.recordCosmosError(ctx, operation, "unmarshal_failed")
				return nil, goerrors.Errorf("failed to unmarshal memory document: %w", err)
			}
			memories = append(memories, doc.toDomain())
		}
	}

	return memories, nil
}

// deleteIDBatch executes a transactional batch delete for the given IDs.
// alreadyDeleted is the count of successfully deleted items in prior batches,
// used for error reporting.
func (r *cosmosMemoryStore) deleteIDBatch(ctx context.Context, pk azcosmos.PartitionKey, ids []string, operation string, alreadyDeleted int) error {
	batch := r.container.NewTransactionalBatch(pk)
	for _, id := range ids {
		batch.DeleteItem(id, nil)
	}

	batchResp, err := r.container.ExecuteTransactionalBatch(ctx, batch, nil)
	if err != nil {
		r.recordCosmosErrorFromAzure(ctx, operation, err)
		return goerrors.Errorf("failed to execute transactional batch delete (deleted %d so far): %w", alreadyDeleted, err)
	}
	if !batchResp.Success {
		r.recordCosmosError(ctx, operation, "batch_partial_failure")
		// Batching follows an all-or-nothing approach. If any operation fails,
		// the entire batch is considered failed.
		// The failing operation will have the "real" status code corresponding
		// to the error. All other operations will have a 424 status code
		// (Failed Dependency) to indicate they were not executed.
		var errs []error
		for _, result := range batchResp.OperationResults {
			if result.StatusCode == http.StatusFailedDependency {
				continue
			}
			errs = append(errs, goerrors.Errorf("batch delete operation returned status %d", result.StatusCode))
		}
		return goerrors.Errorf("transactional batch delete failed (deleted %d so far): %w", alreadyDeleted, errors.Join(errs...))
	}
	return nil
}

func (r *cosmosMemoryStore) recordDuration(ctx context.Context, operation string, startTime time.Time) {
	duration := time.Since(startTime)
	r.obsv.DistributionMs(ctx, metricCosmosOperationDuration, map[string]string{
		"operation": operation,
	}, duration)
}

// recordCosmosError records a Cosmos-specific error metric.
func (r *cosmosMemoryStore) recordCosmosError(ctx context.Context, operation, errorType string) {
	r.obsv.Increment(ctx, metricCosmosErrorCount, map[string]string{
		"operation":  operation,
		"error_type": errorType,
	})
}

func (r *cosmosMemoryStore) recordQueryResponseMetrics(ctx context.Context, operation string, response azcosmos.QueryItemsResponse) {
	r.obsv.Distribution(ctx, metricCosmosRequestCharge, map[string]string{
		"operation": operation,
	}, float64(response.RequestCharge))
	r.obsv.Distribution(ctx, metricCosmosReturnedItemCount, map[string]string{
		"operation": operation,
	}, float64(len(response.Items)))
}

// recordCosmosErrorFromAzure extracts error details from Azure SDK errors and records them.
func (r *cosmosMemoryStore) recordCosmosErrorFromAzure(ctx context.Context, operation string, err error) {
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
	r.recordCosmosError(ctx, operation, errorType)
}

func isCosmosThrottled(err error) bool {
	var responseErr *azcore.ResponseError
	return errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusTooManyRequests
}

func isCosmosBadRequest(err error) bool {
	var responseErr *azcore.ResponseError
	return errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusBadRequest
}

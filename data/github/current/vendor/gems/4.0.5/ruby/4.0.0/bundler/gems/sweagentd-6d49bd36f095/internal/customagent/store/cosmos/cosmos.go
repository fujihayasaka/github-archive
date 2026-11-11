// Package cosmos provides a CosmosDB implementation of custom agent storage.
package cosmos

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/go-stats"
	cosmosclient "github.com/github/sweagentd/internal/cosmos"
	"github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

const (
	metricOperationDuration = "customagent_cosmos.operation_duration"
	metricErrorCount        = "customagent_cosmos.error_count"
	metricPayloadSize       = "customagent_cosmos.payload_size"
)

// Store is a CosmosDB implementation of custom agent storage.
type Store struct {
	container *azcosmos.ContainerClient
	obsv      observability.Exporters
}

// NewStore creates a store from an existing container client.
func NewStore(container *azcosmos.ContainerClient, obsv observability.Exporters) *Store {
	return &Store{
		container: container,
		obsv:      obsv,
	}
}

// NewStoreFromOpts creates a store using shared cosmos client construction.
func NewStoreFromOpts(opts *cosmosclient.ContainerOpts) (*Store, error) {
	if opts == nil {
		return nil, goerrors.New("cosmos options cannot be nil")
	}

	container, err := cosmosclient.NewCosmosContainerClient(opts)
	if err != nil {
		return nil, goerrors.Errorf("failed to create cosmos container client: %w", err)
	}

	return NewStore(container, opts.Obsv), nil
}

func partitionKey(scopeID int64) azcosmos.PartitionKey {
	return azcosmos.NewPartitionKey().AppendNumber(float64(scopeID))
}

// Upsert creates or updates an agent record.
func (s *Store) Upsert(ctx context.Context, record *store.AgentRecord) (*store.AgentRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.cosmos.Store.Upsert")
	startTime := time.Now()
	operation := "upsert"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	if record == nil {
		return nil, goerrors.New("agent record cannot be nil")
	}

	record.SetTimestamps()

	pk := partitionKey(record.ScopeID)

	data, err := json.Marshal(record)
	if err != nil {
		s.recordError(ctx, operation, "marshal_failed")
		return nil, goerrors.Errorf("failed to marshal agent record: %w", err)
	}

	s.obsv.Statter.Distribution(metricPayloadSize, s.obsv.TelemetryTags(ctx).Merge(stats.Tags{"operation": operation}), float64(len(data)))

	resp, err := s.container.UpsertItem(ctx, pk, data, nil)
	if err != nil {
		s.recordErrorFromAzure(ctx, operation, err)
		return nil, goerrors.Errorf("failed to upsert agent record: %w", err)
	}

	var result store.AgentRecord
	err = json.Unmarshal(resp.Value, &result)
	if err != nil {
		s.recordError(ctx, operation, "unmarshal_failed")
		return nil, goerrors.Errorf("failed to unmarshal upsert response: %w", err)
	}

	return &result, nil
}

// Get retrieves a single agent record by ID.
func (s *Store) Get(ctx context.Context, scopeID int64, id string) (*store.AgentRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.cosmos.Store.Get")
	startTime := time.Now()
	operation := "get"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	pk := partitionKey(scopeID)

	resp, err := s.container.ReadItem(ctx, pk, id, nil)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusNotFound {
			return nil, store.ErrAgentNotFound
		}
		s.recordErrorFromAzure(ctx, operation, err)
		return nil, goerrors.Errorf("failed to get agent record: %w", err)
	}

	var record store.AgentRecord
	err = json.Unmarshal(resp.Value, &record)
	if err != nil {
		s.recordError(ctx, operation, "unmarshal_failed")
		return nil, goerrors.Errorf("failed to unmarshal agent record: %w", err)
	}

	return &record, nil
}

// GetByPath retrieves an agent record by file path within a scope partition.
func (s *Store) GetByPath(ctx context.Context, scopeID int64, path string) (*store.AgentRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.cosmos.Store.GetByPath")
	startTime := time.Now()
	operation := "get_by_path"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	pk := partitionKey(scopeID)

	query := "SELECT * FROM c WHERE c.scope_id = @scope_id AND c.path = @path"
	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@scope_id", Value: scopeID},
			{Name: "@path", Value: path},
		},
	}

	pager := s.container.NewQueryItemsPager(query, pk, &opt)

	records, err := s.getAllRecordsFromPager(ctx, pager, operation)
	if err != nil {
		return nil, goerrors.Errorf("failed to query agent by path: %w", err)
	}

	if len(records) == 0 {
		return nil, store.ErrAgentNotFound
	}

	return records[0], nil
}

// List retrieves all agent records for a scope partition.
func (s *Store) List(ctx context.Context, scopeID int64) ([]*store.AgentRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.cosmos.Store.List")
	startTime := time.Now()
	operation := "list"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	pk := partitionKey(scopeID)

	query := "SELECT * FROM c WHERE c.scope_id = @scope_id"
	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@scope_id", Value: scopeID},
		},
	}

	pager := s.container.NewQueryItemsPager(query, pk, &opt)

	records, err := s.getAllRecordsFromPager(ctx, pager, operation)
	if err != nil {
		return nil, goerrors.Errorf("failed to list agent records: %w", err)
	}

	return records, nil
}

// Delete removes a single agent record by ID.
func (s *Store) Delete(ctx context.Context, scopeID int64, id string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.cosmos.Store.Delete")
	startTime := time.Now()
	operation := "delete"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	pk := partitionKey(scopeID)

	_, err := s.container.DeleteItem(ctx, pk, id, nil)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusNotFound {
			return store.ErrAgentNotFound
		}
		s.recordErrorFromAzure(ctx, operation, err)
		return goerrors.Errorf("failed to delete agent record: %w", err)
	}

	return nil
}

// DeleteByScopeID removes all agent records for a given scope partition.
func (s *Store) DeleteByScopeID(ctx context.Context, scopeID int64) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.cosmos.Store.DeleteByScopeID")
	startTime := time.Now()
	operation := "delete_by_scope_id"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	records, err := s.List(ctx, scopeID)
	if err != nil {
		return goerrors.Errorf("failed to list agents for deletion: %w", err)
	}

	for _, record := range records {
		err = s.Delete(ctx, scopeID, record.ID)
		if err != nil {
			return goerrors.Errorf("failed to delete agent record %s: %w", record.ID, err)
		}
	}

	return nil
}

func (s *Store) getAllRecordsFromPager(ctx context.Context, pager *runtime.Pager[azcosmos.QueryItemsResponse], operation string) ([]*store.AgentRecord, error) {
	var records []*store.AgentRecord

	for pager.More() {
		resp, err := pager.NextPage(ctx)
		if err != nil {
			s.recordErrorFromAzure(ctx, operation, err)
			return nil, err
		}

		for _, item := range resp.Items {
			var record store.AgentRecord
			err = json.Unmarshal(item, &record)
			if err != nil {
				s.recordError(ctx, operation, "unmarshal_failed")
				return nil, goerrors.Errorf("failed to unmarshal agent record: %w", err)
			}
			records = append(records, &record)
		}
	}

	return records, nil
}

func (s *Store) recordDuration(ctx context.Context, operation string, startTime time.Time) {
	duration := time.Since(startTime)
	s.obsv.DistributionMs(ctx, metricOperationDuration, stats.Tags{
		"operation": operation,
	}, duration)
}

func (s *Store) recordError(ctx context.Context, operation, errorType string) {
	s.obsv.Increment(ctx, metricErrorCount, stats.Tags{
		"operation":  operation,
		"error_type": errorType,
	})
}

func (s *Store) recordErrorFromAzure(ctx context.Context, operation string, err error) {
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
		case http.StatusConflict, http.StatusPreconditionFailed:
			errorType = "conflict"
		default:
			errorType = "azure_error"
		}
	}
	s.recordError(ctx, operation, errorType)
}

// Package cosmos provides a CosmosDB implementation of interval trigger storage.
package cosmos

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"sort"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/go-stats"
	cosmosclient "github.com/github/sweagentd/internal/cosmos"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
)

const (
	metricOperationDuration = "scheduler_cosmos.operation_duration"
	metricErrorCount        = "scheduler_cosmos.error_count"
	metricPayloadSize       = "scheduler_cosmos.payload_size"
)

// ErrNotFound is returned when a trigger record does not exist.
var ErrNotFound = errors.New("interval trigger not found")

// ErrConflict is returned when an optimistic concurrency check fails.
var ErrConflict = errors.New("precondition failed: stale version")

// Store is a CosmosDB implementation of interval trigger storage.
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

// Upsert creates or updates an interval trigger record.
func (s *Store) Upsert(ctx context.Context, trigger *schedulerstore.IntervalTriggerRecord) (*schedulerstore.IntervalTriggerRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "scheduler.cosmos.Store.Upsert")
	startTime := time.Now()
	operation := "upsert"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	if trigger == nil {
		return nil, goerrors.New("interval trigger cannot be nil")
	}

	trigger.SetTimestamps()

	pk := partitionKey(trigger.ScopeID)

	data, err := json.Marshal(trigger)
	if err != nil {
		s.recordError(ctx, operation, "marshal_failed")
		return nil, goerrors.Errorf("failed to marshal interval trigger: %w", err)
	}

	s.obsv.Statter.Distribution(metricPayloadSize, s.obsv.TelemetryTags(ctx).Merge(stats.Tags{"operation": operation}), float64(len(data)))

	resp, err := s.container.UpsertItem(ctx, pk, data, nil)
	if err != nil {
		s.recordErrorFromAzure(ctx, operation, err)
		return nil, goerrors.Errorf("failed to upsert interval trigger: %w", err)
	}

	var result schedulerstore.IntervalTriggerRecord
	err = json.Unmarshal(resp.Value, &result)
	if err != nil {
		s.recordError(ctx, operation, "unmarshal_failed")
		return nil, goerrors.Errorf("failed to unmarshal upsert response: %w", err)
	}

	return &result, nil
}

// Get retrieves a single interval trigger by scope and ID.
func (s *Store) Get(ctx context.Context, scopeID int64, id string) (*schedulerstore.IntervalTriggerRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "scheduler.cosmos.Store.Get")
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
			return nil, ErrNotFound
		}
		s.recordErrorFromAzure(ctx, operation, err)
		return nil, goerrors.Errorf("failed to get interval trigger: %w", err)
	}

	var result schedulerstore.IntervalTriggerRecord
	err = json.Unmarshal(resp.Value, &result)
	if err != nil {
		s.recordError(ctx, operation, "unmarshal_failed")
		return nil, goerrors.Errorf("failed to unmarshal interval trigger: %w", err)
	}

	return &result, nil
}

// GetByAgentID retrieves triggers for a specific agent within a scope partition.
func (s *Store) GetByAgentID(ctx context.Context, scopeID int64, agentID string) ([]*schedulerstore.IntervalTriggerRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "scheduler.cosmos.Store.GetByAgentID")
	startTime := time.Now()
	operation := "get_by_agent_id"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	pk := partitionKey(scopeID)

	query := "SELECT * FROM c WHERE c.agent_id = @agent_id"
	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@agent_id", Value: agentID},
		},
	}

	pager := s.container.NewQueryItemsPager(query, pk, &opt)

	triggers, err := s.getAllTriggersFromPager(ctx, pager, operation)
	if err != nil {
		return nil, goerrors.Errorf("failed to get triggers by agent ID: %w", err)
	}

	return triggers, nil
}

// Delete removes an interval trigger by ID within a scope partition.
func (s *Store) Delete(ctx context.Context, scopeID int64, id string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "scheduler.cosmos.Store.Delete")
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
			return ErrNotFound
		}
		s.recordErrorFromAzure(ctx, operation, err)
		return goerrors.Errorf("failed to delete interval trigger: %w", err)
	}

	return nil
}

// ListByScopeID retrieves all interval triggers for a scope partition.
func (s *Store) ListByScopeID(ctx context.Context, scopeID int64) ([]*schedulerstore.IntervalTriggerRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "scheduler.cosmos.Store.ListByScopeID")
	startTime := time.Now()
	operation := "list_by_scope_id"
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

	triggers, err := s.getAllTriggersFromPager(ctx, pager, operation)
	if err != nil {
		return nil, goerrors.Errorf("failed to list interval triggers: %w", err)
	}

	return triggers, nil
}

// FindDueTriggers returns triggers that are due for execution (next_run_at <= now AND locked_by = "").
// This is a cross-partition query. The Azure Cosmos DB Gateway API used by the
// Go SDK only supports simple projections and filtering for cross-partition
// queries, so ORDER BY and TOP are applied client-side.
func (s *Store) FindDueTriggers(ctx context.Context, now time.Time, limit int) ([]*schedulerstore.IntervalTriggerRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "scheduler.cosmos.Store.FindDueTriggers")
	startTime := time.Now()
	operation := "find_due_triggers"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	if limit <= 0 {
		return nil, nil
	}

	query := "SELECT * FROM c WHERE c.next_run_at <= @now AND c.locked_by = ''"
	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@now", Value: now.Unix()},
		},
	}

	pager := s.container.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	triggers, err := s.getAllTriggersFromPager(ctx, pager, operation)
	if err != nil {
		return nil, goerrors.Errorf("failed to find due triggers: %w", err)
	}

	sort.Slice(triggers, func(i, j int) bool {
		return triggers[i].NextRunAt < triggers[j].NextRunAt
	})

	if len(triggers) > limit {
		triggers = triggers[:limit]
	}

	return triggers, nil
}

// FindStaleLocks returns triggers with locks older than the threshold.
// This is a cross-partition query for stale lock recovery. TOP is applied
// client-side because the Gateway API only supports simple projections and
// filtering for cross-partition queries.
func (s *Store) FindStaleLocks(ctx context.Context, threshold time.Time, limit int) ([]*schedulerstore.IntervalTriggerRecord, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "scheduler.cosmos.Store.FindStaleLocks")
	startTime := time.Now()
	operation := "find_stale_locks"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	if limit <= 0 {
		return nil, nil
	}

	query := "SELECT * FROM c WHERE c.locked_by != '' AND c.locked_at < @threshold"
	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@threshold", Value: threshold.Unix()},
		},
	}

	pager := s.container.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	triggers, err := s.getAllTriggersFromPager(ctx, pager, operation)
	if err != nil {
		return nil, goerrors.Errorf("failed to find stale locks: %w", err)
	}

	if len(triggers) > limit {
		triggers = triggers[:limit]
	}

	return triggers, nil
}

// PatchTrigger applies a partial update to an interval trigger using Cosmos patch operations.
// Only non-nil fields in the patch are applied. Uses ETag-based optimistic concurrency.
// Returns the new ETag from the response so callers can chain patches without re-reading.
func (s *Store) PatchTrigger(ctx context.Context, scopeID int64, id string, patch schedulerstore.IntervalTriggerPatch) (*azcore.ETag, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "scheduler.cosmos.Store.PatchTrigger")
	startTime := time.Now()
	operation := "patch_trigger"
	defer func() {
		s.recordDuration(ctx, operation, startTime)
		span.End()
	}()

	pk := partitionKey(scopeID)

	ops := azcosmos.PatchOperations{}
	if patch.LockedBy != nil {
		ops.AppendSet("/locked_by", *patch.LockedBy)
	}
	if patch.LockedAt != nil {
		ops.AppendSet("/locked_at", *patch.LockedAt)
	}
	if patch.NextRunAt != nil {
		ops.AppendSet("/next_run_at", *patch.NextRunAt)
	}
	if patch.LastRunAt != nil {
		ops.AppendSet("/last_run_at", *patch.LastRunAt)
	}
	if patch.IntervalType != nil {
		ops.AppendSet("/interval_type", *patch.IntervalType)
	}
	if patch.AnchorHourUTC != nil {
		ops.AppendSet("/anchor_hour_utc", *patch.AnchorHourUTC)
	}
	if patch.AnchorDayOfWeek != nil {
		ops.AppendSet("/anchor_day_of_week", *patch.AnchorDayOfWeek)
	}
	if patch.ActorID != nil {
		ops.AppendSet("/actor_id", *patch.ActorID)
	}
	if patch.ActorLogin != nil {
		ops.AppendSet("/actor_login", *patch.ActorLogin)
	}
	if patch.TreeOID != nil {
		ops.AppendSet("/tree_oid", *patch.TreeOID)
	}
	if patch.LastEventUpdatedAt != nil {
		ops.AppendSet("/last_event_updated_at", *patch.LastEventUpdatedAt)
	}

	opts := &azcosmos.ItemOptions{}
	if patch.ETag != nil {
		opts.IfMatchEtag = patch.ETag
	}

	resp, err := s.container.PatchItem(ctx, pk, id, ops, opts)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) {
			if responseErr.StatusCode == http.StatusPreconditionFailed || responseErr.StatusCode == http.StatusConflict {
				return nil, ErrConflict
			}
			if responseErr.StatusCode == http.StatusNotFound {
				return nil, ErrNotFound
			}
		}
		s.recordErrorFromAzure(ctx, operation, err)
		return nil, goerrors.Errorf("failed to patch trigger: %w", err)
	}

	return &resp.ETag, nil
}

func (s *Store) getAllTriggersFromPager(ctx context.Context, pager *runtime.Pager[azcosmos.QueryItemsResponse], operation string) ([]*schedulerstore.IntervalTriggerRecord, error) {
	var triggers []*schedulerstore.IntervalTriggerRecord

	for pager.More() {
		resp, err := pager.NextPage(ctx)
		if err != nil {
			s.recordErrorFromAzure(ctx, operation, err)
			return nil, err
		}

		for _, item := range resp.Items {
			var trigger schedulerstore.IntervalTriggerRecord
			err = json.Unmarshal(item, &trigger)
			if err != nil {
				s.recordError(ctx, operation, "unmarshal_failed")
				return nil, goerrors.Errorf("failed to unmarshal interval trigger: %w", err)
			}
			triggers = append(triggers, &trigger)
		}
	}

	return triggers, nil
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

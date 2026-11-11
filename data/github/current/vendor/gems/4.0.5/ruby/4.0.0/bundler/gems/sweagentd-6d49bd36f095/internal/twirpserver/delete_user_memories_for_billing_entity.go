package twirpserver

import (
	"context"
	"errors"

	"github.com/github/sweagentd/internal/featureflags"
	memorycore "github.com/github/sweagentd/internal/memory/core"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
)

const (
	// Cosmos DB transactional batches are limited to 100 operations,
	// so we cap each delete page to that ceiling.
	defaultBillingEntityMemoryDeleteLimit uint = 100
	maxBillingEntityMemoryDeleteLimit     uint = 100
)

// DeleteUserMemoriesForBillingEntity deletes one bounded page of memories
// from a single user partition within a billing entity.
func (s *Server) DeleteUserMemoriesForBillingEntity(ctx context.Context, req *jobs_pb.DeleteUserMemoriesForBillingEntityRequest) (*jobs_pb.DeleteUserMemoriesForBillingEntityResponse, error) {
	// 1. Validate raw request fields.
	if req == nil {
		return nil, twirp.RequiredArgumentError("request")
	}
	if req.GetUserId() == 0 {
		return nil, twirp.RequiredArgumentError("user_id")
	}
	if req.GetSnapshotTime() == nil {
		return nil, twirp.RequiredArgumentError("snapshot_time")
	}
	err := req.GetSnapshotTime().CheckValid()
	if err != nil {
		return nil, twirp.InvalidArgumentError("snapshot_time", "snapshot_time must be a valid timestamp")
	}

	// 2. Check system is configured.
	if s.ffClient == nil {
		return nil, twirp.InternalError("feature flag client is not configured")
	}
	if s.memoryService == nil {
		return nil, twirp.InternalError("billing entity memory service is not configured")
	}

	// 3. Build and validate billing filter.
	filter := memorycore.BillingEntityMemoryFilter{
		OrganizationID: req.GetOrganizationId(),
		EnterpriseID:   req.GetEnterpriseId(),
		UserID:         req.GetUserId(),
	}
	if filter.IsZero() {
		return nil, twirp.InvalidArgumentError("organization_id", "organization_id or enterprise_id is required")
	}

	// 4. Check feature flag (needs the filter for org/enterprise actors).
	if !s.ffClient.IsEnabled(ctx, featureflags.CopilotMemoryAdminExports, billingEntityMemoryExportActors(filter)...) {
		return nil, twirp.NotFoundError("copilot memory admin exports are not enabled")
	}

	// 5. Clamp limit and execute.
	limit := uint(req.GetLimit())
	if limit == 0 {
		limit = defaultBillingEntityMemoryDeleteLimit
	} else if limit > maxBillingEntityMemoryDeleteLimit {
		limit = maxBillingEntityMemoryDeleteLimit
	}

	// Caller must loop with the returned continuation token until empty
	// to delete all memories for this user within the billing entity.
	var result *memorycore.BillingEntityDeleteResult
	result, err = s.memoryService.DeleteBillingEntityMemories(ctx, filter, memorycore.MemoryPageRequest{
		Limit:             limit,
		ContinuationToken: req.GetContinuationToken(),
		SnapshotTime:      req.GetSnapshotTime().AsTime(),
	})
	if err != nil {
		if errors.Is(err, memorycore.ErrInvalidBillingFilter) {
			return nil, twirp.InvalidArgumentError("organization_id", "organization_id or enterprise_id is required")
		}
		if errors.Is(err, memorycore.ErrInvalidUserFilter) {
			return nil, twirp.InvalidArgumentError("user_id", "user_id is required")
		}
		if errors.Is(err, memorycore.ErrInvalidSnapshotTime) {
			return nil, twirp.InvalidArgumentError("snapshot_time", "snapshot_time is required")
		}
		if errors.Is(err, memorycore.ErrInvalidContinuation) {
			return nil, twirp.InvalidArgumentError("continuation_token", "continuation_token is invalid")
		}
		if errors.Is(err, memorycore.ErrMemoryStoreThrottled) {
			return nil, twirp.ResourceExhausted.Error("memory store is throttled, please retry later")
		}
		return nil, twirp.InternalError("failed to delete user memories for billing entity")
	}
	if result == nil {
		result = &memorycore.BillingEntityDeleteResult{}
	}

	return &jobs_pb.DeleteUserMemoriesForBillingEntityResponse{
		DeletedCount:      uint32(result.DeletedCount),
		ContinuationToken: result.ContinuationToken,
	}, nil
}

package twirpserver

import (
	"context"
	"errors"
	"strconv"

	"github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/feature-management-client-go/vexi/v2/extensions"
	"github.com/github/sweagentd/internal/featureflags"
	memorycore "github.com/github/sweagentd/internal/memory/core"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const (
	defaultBillingEntityMemoryPageLimit uint = 100
	maxBillingEntityMemoryPageLimit     uint = 100
)

type memoryService interface {
	ListBillingEntityMemories(ctx context.Context, filter memorycore.BillingEntityMemoryFilter, pageRequest memorycore.MemoryPageRequest) (*memorycore.MemoryPage, error)
	DeleteBillingEntityMemories(ctx context.Context, filter memorycore.BillingEntityMemoryFilter, pageRequest memorycore.MemoryPageRequest) (*memorycore.BillingEntityDeleteResult, error)
}

// WithMemoryService configures the service used by memory RPCs.
func (s *Server) WithMemoryService(memoryService memoryService) *Server {
	s.memoryService = memoryService
	return s
}

// ListUserMemoriesForBillingEntity returns a billing-scoped page from one user's memory partition.
func (s *Server) ListUserMemoriesForBillingEntity(ctx context.Context, req *jobs_pb.ListUserMemoriesForBillingEntityRequest) (*jobs_pb.ListUserMemoriesForBillingEntityResponse, error) {
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

	filter := memorycore.BillingEntityMemoryFilter{
		OrganizationID: req.GetOrganizationId(),
		EnterpriseID:   req.GetEnterpriseId(),
		UserID:         req.GetUserId(),
	}
	if filter.IsZero() {
		return nil, twirp.InvalidArgumentError("organization_id", "organization_id or enterprise_id is required")
	}
	if s.ffClient == nil {
		return nil, twirp.InternalError("feature flag client is not configured")
	}
	if !s.ffClient.IsEnabled(ctx, featureflags.CopilotMemoryAdminExports, billingEntityMemoryExportActors(filter)...) {
		return nil, twirp.NotFoundError("copilot memory admin exports are not enabled")
	}
	if s.memoryService == nil {
		return nil, twirp.InternalError("billing entity memory service is not configured")
	}

	limit := uint(req.GetLimit())
	if limit == 0 {
		limit = defaultBillingEntityMemoryPageLimit
	} else if limit > maxBillingEntityMemoryPageLimit {
		limit = maxBillingEntityMemoryPageLimit
	}

	page, err := s.memoryService.ListBillingEntityMemories(ctx, filter, memorycore.MemoryPageRequest{
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
		return nil, twirp.InternalError("failed to list user memories for billing entity")
	}
	if page == nil {
		page = &memorycore.MemoryPage{}
	}

	return &jobs_pb.ListUserMemoriesForBillingEntityResponse{
		Memories:          memoriesToProto(page.Memories),
		ContinuationToken: page.ContinuationToken,
	}, nil
}

// billingEntityMemoryExportActors returns Vexi actors for the supplied billing scope.
func billingEntityMemoryExportActors(filter memorycore.BillingEntityMemoryFilter) []vexi.Actor {
	actors := make([]vexi.Actor, 0, 2)
	if filter.OrganizationID != 0 {
		actors = append(actors, extensions.NewOrganization(strconv.FormatUint(filter.OrganizationID, 10)))
	}
	if filter.EnterpriseID != 0 {
		actors = append(actors, extensions.NewBusiness(strconv.FormatUint(filter.EnterpriseID, 10)))
	}
	return actors
}

func memoriesToProto(memories []*memorycore.Memory) []*jobs_pb.Memory {
	protoMemories := make([]*jobs_pb.Memory, 0, len(memories))
	for _, memory := range memories {
		if memory == nil {
			continue
		}
		protoMemories = append(protoMemories, memoryToProto(memory))
	}
	return protoMemories
}

func memoryToProto(memory *memorycore.Memory) *jobs_pb.Memory {
	return &jobs_pb.Memory{
		Id:        memory.ID.String(),
		Subject:   memory.Subject,
		Fact:      memory.Fact,
		Citations: memory.Citations,
		Reason:    memory.Reason,
		Source: &jobs_pb.MemorySource{
			InteractionId: memory.Source.InteractionID,
			Agent:         memory.Source.Agent,
			CommitSha:     memory.Source.CommitSHA,
			BaseModel:     memory.Source.BaseModel,
			UserId:        memory.Source.User.ID,
			UserLogin:     memory.Source.User.Login,
		},
		CreatedAt: timestamppb.New(memory.CreatedAt),
		UpdatedAt: timestamppb.New(memory.UpdatedAt),
	}
}

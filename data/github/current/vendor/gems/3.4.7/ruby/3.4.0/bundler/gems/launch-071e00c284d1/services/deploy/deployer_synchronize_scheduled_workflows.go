package deploy

import (
	"context"

	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
)

func (s *service) SynchronizeScheduledWorkflows(ctx context.Context, req *launchtypes.SynchronizeScheduledWorkflowsRequest) (*emptypb.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoGid, err := s.GetGlobalIDFromIdentity(ctx, req.GetRepositoryNodeId(), "SynchronizeScheduledWorkflows")
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}
	req.RepositoryNodeId = types.IdentityFromGlobalID(repoGid)
	actorGid, err := s.GetGlobalIDFromIdentity(ctx, req.GetActorNodeId(), "SynchronizeScheduledWorkflows")
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}
	req.ActorNodeId = types.IdentityFromGlobalID(actorGid)
	return s.cfg.ScheduleManager.SynchronizeScheduledWorkflows(ctx, req)
}

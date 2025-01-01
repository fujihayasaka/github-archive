package deploy

import (
	"context"

	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
)

func (s *service) DisableScheduledWorkflow(ctx context.Context, req *launchtypes.DisableScheduledWorkflowRequest) (*emptypb.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoGid, err := s.GetGlobalIDFromIdentity(ctx, req.GetRepositoryNodeId(), "DisableScheduledWorkflow")
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}
	req.RepositoryNodeId = types.IdentityFromGlobalID(repoGid)
	return s.cfg.ScheduleManager.DisableScheduledWorkflow(ctx, req)
}

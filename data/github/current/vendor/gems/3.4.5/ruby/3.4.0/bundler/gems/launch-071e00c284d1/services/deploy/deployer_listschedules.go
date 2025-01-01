package deploy

import (
	"context"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
)

func (s *service) ListSchedules(ctx context.Context, req *launchtypes.ListSchedulesRequest) (*launchtypes.ListSchedulesResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoGid, err := s.GetGlobalIDFromIdentity(ctx, req.GetRepositoryNodeId(), "ListSchedules")
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}
	req.RepositoryNodeId = types.IdentityFromGlobalID(repoGid)
	return s.cfg.ScheduleManager.ListSchedules(ctx, req)
}

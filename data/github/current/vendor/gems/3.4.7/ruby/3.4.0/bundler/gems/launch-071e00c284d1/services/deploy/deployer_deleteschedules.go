package deploy

import (
	"context"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
)

func (s *service) DeleteSchedules(ctx context.Context, req *launchtypes.DeleteSchedulesRequest) (*launchtypes.DeleteSchedulesResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoGid, err := s.GetGlobalIDFromIdentity(ctx, req.GetRepositoryNodeId(), "DeleteSchedules")
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}
	req.RepositoryNodeId = types.IdentityFromGlobalID(repoGid)
	return s.cfg.ScheduleManager.DeleteSchedules(ctx, req)
}

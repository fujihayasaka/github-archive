package schedulemanager

import (
	"context"

	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
)

// DeleteSchedules fulfills a DeleteSchedulesRequest, which deletes scheduled workflows for a repository
func (s *service) DeleteSchedules(ctx context.Context, req *launchtypes.DeleteSchedulesRequest) (*launchtypes.DeleteSchedulesResponse, error) {
	globalID := types.IdentityToGlobalID(ctx, req.GetRepositoryNodeId())

	rowsDeleted, err := s.store.DeleteSchedulesForRepository(ctx, launchconfig.AppEnv(req.GetEnvironment()), globalID)
	if err != nil {
		return nil, err
	}
	return &launchtypes.DeleteSchedulesResponse{
		Count: rowsDeleted,
	}, nil
}

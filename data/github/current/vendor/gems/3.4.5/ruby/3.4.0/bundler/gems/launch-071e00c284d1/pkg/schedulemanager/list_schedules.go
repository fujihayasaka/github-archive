package schedulemanager

import (
	"context"

	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
)

// ListSchedules fulfills a ListSchedulesRequest, which lists scheduled workflows for a repository
func (s *service) ListSchedules(ctx context.Context, req *launchtypes.ListSchedulesRequest) (*launchtypes.ListSchedulesResponse, error) {
	nodeID := types.IdentityToGlobalID(ctx, req.GetRepositoryNodeId())
	schedules, err := s.store.ListSchedulesForRepository(ctx, launchconfig.AppEnv(req.GetEnvironment()), nodeID)
	if err != nil {
		return nil, err
	}

	response := launchtypes.ListSchedulesResponse{}
	response.WorkflowSchedules = make([]*launchtypes.WorkflowSchedule, 0, len(schedules))
	for _, s := range schedules {
		rs := launchtypes.WorkflowSchedule{
			Id:                 s.ID,
			ScheduleHash:       s.ScheduleHash,
			ScheduleNextHash:   s.ScheduleNextHash,
			RepositoryNodeId:   types.IdentityFromGlobalID(s.RepositoryNodeID),
			RepositoryNextId:   types.IdentityFromGlobalID(s.RepositoryNextID),
			WorkflowIdentifier: s.WorkflowIdentifier,
			WorkflowFilePath:   s.WorkflowFilePath,
			Environment:        s.Environment,
			Schedule:           s.Schedule,
			ScatterOffset:      s.ScatterOffset,
			NextRunAt:          timestamppb.New(s.NextRunAt),
			CommitSha:          s.CommitSHA.String(),
			ActorNodeId:        types.IdentityFromGlobalID(s.ActorNodeID),
			ActorNextId:        types.IdentityFromGlobalID(s.ActorNextID),
			ActorLogin:         s.ActorLogin,
			Tier:               int64(s.Tier),
		}
		if s.CreatedAt != nil {
			rs.CreatedAt = timestamppb.New(*s.CreatedAt)
		}
		if s.TierUpdatedAt != nil {
			rs.TierUpdatedAt = timestamppb.New(*s.TierUpdatedAt)
		}
		if s.OwnerID != nil {
			rs.OwnerId = *s.OwnerID
		}
		response.WorkflowSchedules = append(response.WorkflowSchedules, &rs)
	}

	return &response, nil
}

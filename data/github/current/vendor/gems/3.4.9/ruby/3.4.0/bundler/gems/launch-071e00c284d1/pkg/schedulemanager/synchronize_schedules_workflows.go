package schedulemanager

import (
	context "context"

	emptypb "google.golang.org/protobuf/types/known/emptypb"

	launchtypes "github.com/github/launch/services/pbtypes/launchtypes"
	types "github.com/github/launch/types"
)

func (s *service) SynchronizeScheduledWorkflows(ctx context.Context, req *launchtypes.SynchronizeScheduledWorkflowsRequest) (*emptypb.Empty, error) {
	s.SyncOnPush(
		ctx,
		types.IdentityToGlobalID(ctx, req.GetRepositoryNodeId()),
		types.GitRef(req.GetRef()),
		types.IdentityToGlobalID(ctx, req.GetActorNodeId()),
		req.GetOwnerDatabaseId(),
	)

	return &emptypb.Empty{}, nil
}

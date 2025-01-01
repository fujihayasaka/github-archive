package schedulemanager

import (
	context "context"

	emptypb "google.golang.org/protobuf/types/known/emptypb"

	"github.com/github/launch/pkg/launchconfig"
	launchtypes "github.com/github/launch/services/pbtypes/launchtypes"
	types "github.com/github/launch/types"
)

func (s *service) DisableScheduledWorkflow(ctx context.Context, req *launchtypes.DisableScheduledWorkflowRequest) (*emptypb.Empty, error) {
	repoID := types.IdentityToGlobalID(ctx, req.GetRepositoryNodeId())
	workflowFilePath := req.GetWorkflowFilePath()

	_, err := s.store.DeleteScheduleForWorkflow(
		ctx,
		launchconfig.AppEnv(req.GetEnvironment()),
		repoID,
		workflowFilePath,
	)

	if err != nil {
		return nil, err
	}

	return &emptypb.Empty{}, nil
}

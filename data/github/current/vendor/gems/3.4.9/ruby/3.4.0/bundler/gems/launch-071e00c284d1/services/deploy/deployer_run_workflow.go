package deploy

import (
	"context"

	"github.com/twitchtv/twirp"

	pb "github.com/github/launch/services/pb/deploy"
)

func (s *service) RunWorkflow(ctx context.Context, req *pb.RunWorkflowRequest) (*pb.RunWorkflowResponse, error) {
	return nil, twirp.NewError(twirp.Unimplemented, "not yet implemented")
}

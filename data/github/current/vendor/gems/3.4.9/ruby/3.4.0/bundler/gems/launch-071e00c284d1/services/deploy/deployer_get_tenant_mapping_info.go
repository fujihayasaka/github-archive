package deploy

import (
	"context"

	"github.com/twitchtv/twirp"

	"github.com/github/launch/observability/tracing"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
)

func (s *service) GetTenantMappingInfo(ctx context.Context, req *pb.GetTenantMappingInfoRequest) (*pb.GetTenantMappingInfoResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	res, found, err := s.cfg.AZPResourcesLoader.GetByGlobalID(ctx, types.IdentityToGlobalID(ctx, req.EntityId), req.Environment)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if !found {
		return nil, twirp.NotFoundError("no tenant mapping found")
	}

	return &pb.GetTenantMappingInfoResponse{
		TenantId:             res.TenantID,
		EntityId:             req.EntityId,
		Environment:          req.Environment,
		PipelinesScaleUnitId: res.PipelinesScaleUnitID.String(),
	}, nil
}

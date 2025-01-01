package deploy

import (
	"context"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
)

func (s *service) GetAZForGlobalIDChatops(ctx context.Context, req *pb.GetAZForGlobalIDChatopsRequest) (*pb.GetAZForGlobalIDChatopsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	ctx = ctxstash.WithFields(
		ctx,
		kvp.String("gh.launch.global_id", req.GetGlobalRelayId()),
		kvp.String("gh.launch.request_environment", req.GetEnv()),
	)

	globalID, err := s.gidMigrator.GetNextGlobalID(ctx, req.GetGlobalRelayId())
	if err != nil {
		s.cfg.Obs.Report(ctx, svcerr.NewInternalError("error getting next global ID"), kvp.String("gh.launch.global_id", req.GetGlobalRelayId()), kvp.Err(err))
		return nil, tracing.RecordError(span, err)
	}
	s.LogGlobalIDReplacement(ctx, "GetAZForGlobalIDChatops", req.GetGlobalRelayId(), globalID)

	tenantInfo, found, err := s.cfg.AZPResourcesLoader.GetByGlobalID(ctx, globalID, req.Env)
	if !found {
		return nil, tracing.RecordError(span, svcerr.NewNotFoundError("global id not found in azp_resources"))
	}
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	res := &pb.GetAZForGlobalIDChatopsResponse{
		GlobalID:     globalID.String(),
		AzTenantID:   tenantInfo.TenantID,
		AzTenantName: tenantInfo.TenantName,
	}
	return res, nil
}

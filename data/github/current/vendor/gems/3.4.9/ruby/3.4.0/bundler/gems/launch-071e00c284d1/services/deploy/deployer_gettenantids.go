package deploy

import (
	"context"
	"fmt"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	pb "github.com/github/launch/services/pb/deploy"
)

func (s *service) GetTenantIds(ctx context.Context, req *pb.GetTenantIDsRequest) (*pb.GetTenantIDsResponse, error) {
	// Add tracing
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// Initialize final tenantIDs array with empty strings for each owner id
	tenantIDs := make([]string, len(req.GetOwnerIds()))

	// Find the tenant id for each owner id
	for i, oid := range req.GetOwnerIds() {
		// Get the global owner id
		goid, err := s.GetGlobalIDFromIdentity(ctx, oid, "GetTenantIDs")

		ctxstash.WithFields(
			ctx,
			kvp.String(fmt.Sprintf("owner_id_%d", i), oid.String()),
			kvp.String(fmt.Sprintf("global_owner_id_%d", i), goid.String()),
		)

		// Log if there was an error getting the global owner id
		if err != nil {
			s.cfg.Log.Report(ctx, err)
			continue
		}

		// Get the AZPResources for this owner
		r, err := s.cfg.AZPResources.TryGet(ctx, goid)

		// Log if there was an error getting the AZPResources
		if err != nil {
			s.cfg.Log.Report(ctx, err)
			continue
		}

		tenantIDs[i] = r.TenantID
	}

	return &pb.GetTenantIDsResponse{TenantIds: tenantIDs}, nil
}

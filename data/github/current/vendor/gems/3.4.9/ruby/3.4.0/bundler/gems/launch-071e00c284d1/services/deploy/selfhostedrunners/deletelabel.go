package selfhostedrunners

import (
	"context"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
)

// DeleteLabel deletes the given label on Actions Service
func (s *service) DeleteLabel(ctx context.Context, req *DeleteLabelRequest) (*DeleteLabelResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "deletelabel")

	oid := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if oid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	labelID := req.GetLabelId()

	ctx = ctxstash.WithFields(
		ctx,
		kvp.String("gh.launch.owner.global_id", oid.String()),
		kvp.Int64("gh.launch.label.id", labelID),
	)

	arc, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	err = arc.DeleteLabel(ctx, labelID)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	return &DeleteLabelResponse{Status: "deleted"}, nil
}

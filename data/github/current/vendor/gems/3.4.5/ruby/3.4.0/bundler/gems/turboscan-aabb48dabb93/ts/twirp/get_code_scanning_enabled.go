package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetCodeScanningEnabled(ctx context.Context, req *proto.GetCodeScanningEnabledRequest) (*proto.GetCodeScanningEnabledResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.ByteString("gh.git.ref", req.DefaultRefNameBytes),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	enabled, err := r.statusService.IsCodeScanningEnabled(ctx, repoID, req.DefaultRefNameBytes)
	if err != nil {
		return nil, twerrors.InternalErrorWith(err)
	}

	// To help ensure consumers are up-to-date, publish this status
	// if it hasn't already been published.
	r.statusService.PublishStatusIfChanged(
		ctx, repoID, ts.EnablementReason_OBSERVED_CHANGE, req.DefaultRefNameBytes, &enabled,
	)

	return &proto.GetCodeScanningEnabledResponse{
		IsEnabled: enabled,
	}, nil
}

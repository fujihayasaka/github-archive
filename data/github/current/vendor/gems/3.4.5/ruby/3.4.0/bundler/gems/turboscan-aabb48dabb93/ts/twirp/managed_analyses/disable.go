package managed_analyses

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *Service) Disable(ctx context.Context, req *proto.DisableRequest) (*proto.DisableResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received")

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	err := r.ma.DisableRepo(ctx, ts.RepositoryEID(req.RepositoryId))
	if err != nil && !errors.Is(err, ts.ErrNoChangeRequired) {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	noop := errors.Is(err, ts.ErrNoChangeRequired)
	return &proto.DisableResponse{Noop: noop}, nil
}

package managed_analyses

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/attribute"
)

func (r *Service) Adjust(ctx context.Context, req *proto.AdjustRequest) (*proto.AdjustResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	span.SetAttributes(attribute.Int("gh.repo.id", int(req.RepositoryId)))
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		ts.RepositoryEID(req.RepositoryId).AsKVP(),
		kvp.Strings("gh.turboscan.languages", req.Languages),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}
	repoID := ts.RepositoryEID(req.RepositoryId)

	// We require at least one language to consider the request valid.
	// If the validation run failed for all languages, then there is nothing to adjust.
	if len(req.Languages) == 0 {
		return nil, twerrors.RequiredArgumentError("languages")
	}

	if req.OwnerId == 0 {
		// Logging this so we can eventually turn it into a required field.
		appctx.Logger(ctx).Error("ownerID not set in adjust call", repoID.AsKVP())
	}

	// Forcing the FF for the entire job because we do not have the owner information everywhere
	if req.OwnerId != 0 && flipper.HasCodeScanningActionsYml(ctx, ts.OwnerEID(req.OwnerId), repoID) {
		ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningActionsYml)
	}
	if req.OwnerId != 0 && flipper.HasCodeScanningPrivateRegistry(ctx, ts.OwnerEID(req.OwnerId), repoID) {
		ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningPrivateRegistry)
	}

	err := r.ma.AdjustRepo(ctx, ts.RepositoryEID(req.RepositoryId), req.Languages, ts.WorkflowRunEID(req.WorkflowRunId))
	if err != nil {
		if errors.Is(err, ts.ErrNotOnboarding) {
			return nil, twerrors.NewError(twirp.FailedPrecondition, "repository is not onboarding")
		} else if errors.Is(err, ts.ErrWrongWorkflowRun) {
			return nil, twerrors.NewError(twirp.FailedPrecondition, "wrong workflow run")
		}
		return nil, errors.Wrap(err, "failed to adjust configuration")
	}
	return &proto.AdjustResponse{}, nil
}

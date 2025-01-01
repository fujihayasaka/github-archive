package twirp

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func (r *ResultsResolver) DeleteAnalysis(ctx context.Context, req *proto.DeleteAnalysisRequest) (*proto.DeleteAnalysisResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(attribute.Int("gh.turboscan.analysis_id", int(req.AnalysisId))),
	)
	defer span.End()

	var cancelFunc context.CancelFunc
	ctx, cancelFunc = context.WithTimeout(ctx, 8*time.Second)
	defer cancelFunc()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.analysis_id", req.AnalysisId),
		kvp.Bool("gh.turboscan.confirm_config_delete", req.ConfirmConfigDelete),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if req.AnalysisId == 0 {
		return nil, twerrors.RequiredArgumentError("analysis_id")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)
	analysisID := ts.AnalysisID(req.AnalysisId)
	confirmConfigDeletion := req.ConfirmConfigDelete

	var newMostRecentAnalysis *ts.Analysis
	var err error

	newMostRecentAnalysis, err = r.alertService.SoftDeleteAnalysis(ctx, repoID, analysisID, confirmConfigDeletion)

	if err != nil {
		if errors.Is(err, ts.ErrAnalysisIsNotDeletable) {
			return nil, twerrors.NewError(twirp.InvalidArgument, ErrorMsgAnalysisIsNotDeletable)
		}
		if errors.Is(err, ts.ErrMissingDeletionConfirmation) {
			return nil, twerrors.NewError(twirp.InvalidArgument, ErrorMsgMissingDeletionConfirmation)
		}
		if errors.Is(err, ts.ErrAnalysisNotFound) {
			return nil, o11y.RecordError(span, twerrors.NotFoundError("analysis not found"))
		}
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// Deleting an analysis could cause the enablement status to switch from enabled to not enabled.
	// We need to call the status service to check for a status change.
	// Doing this synchronously during the request might not be ideal but is easier and quick enough at the moment
	// We can switch to a more complicated, async check if we observe problems.
	var ref []byte
	if newMostRecentAnalysis != nil {
		ref = newMostRecentAnalysis.Ref
	}
	fls := false
	r.statusService.PublishStatusIfChanged(ctx, repoID, ts.EnablementReason_DELETED_ANALYSIS, ref, &fls)

	// if reference to newMostRecent is nil then we return an empty response
	if newMostRecentAnalysis == nil {
		return &proto.DeleteAnalysisResponse{}, nil
	}
	return &proto.DeleteAnalysisResponse{
		NewMostRecentAnalysisId: uint64(newMostRecentAnalysis.ID),
	}, nil
}

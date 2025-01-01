package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func (r *ResultsResolver) GetAnalysis(ctx context.Context, req *proto.AnalysisRequest) (*proto.AnalysisResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(attribute.Int("gh.turboscan.analysis_id", int(req.AnalysisId))),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.analysis_id", req.AnalysisId),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if req.AnalysisId == 0 {
		return nil, twerrors.RequiredArgumentError("analysis_id")
	}

	repositoryID := ts.RepositoryEID(req.RepositoryId)
	analysisID := ts.AnalysisID(req.AnalysisId)

	filter := ts.AnalysisFilter{
		RepositoryID:    repositoryID,
		AnalysisIDs:     []ts.AnalysisID{analysisID},
		IncludeOutdated: true,
	}
	opt := &ts.FindOptions{
		Preloads:   []string{"Tool", "ToolVersion"},
		Pagination: &ts.Pagination{Limit: 1},
	}
	analyses, err := r.alertService.FindAnalyses(ctx, filter, opt)
	if err != nil {
		return nil, o11y.RecordError(span, twirp.InternalErrorWith(err))
	}
	if len(analyses) == 0 {
		return nil, twerrors.NotFoundError("analysis not found")
	}
	analysis := analyses[0]
	var out *proto.Analysis
	var msg []*ts.ProcessError
	if analysis.Failed {
		msgs, err := r.alertService.ProcessErrors(ctx, repositoryID, []ts.AnalysisID{analysis.ID})
		if err != nil {
			return nil, o11y.RecordError(span, twirp.InternalErrorWith(err))
		}
		msg = msgs[analysis.ID]
	}

	deletableAnalyses, err := r.alertService.AreAnalysesDeletable(ctx, repositoryID, []ts.Analysis{analysis})
	if err != nil {
		return nil, o11y.RecordError(span, twirp.InternalErrorWith(err))
	}

	out = serializeAnalysis(analysis, msg, deletableAnalyses[analysis.ID])

	return &proto.AnalysisResponse{Analysis: out}, nil
}

package twirp

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
)

func (r *ResultsResolver) GetFilesExtractedSummary(ctx context.Context, req *proto.FilesExtractedSummaryRequest) (*proto.FilesExtractedSummaryResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	var cancelFunc context.CancelFunc
	ctx, cancelFunc = context.WithTimeout(ctx, 8*time.Second)
	defer cancelFunc()

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)

	appctx.Logger(ctx).Info("request received")

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if len(req.Ref) == 0 {
		return nil, twerrors.RequiredArgumentError("ref")
	}

	if req.Tool == "" {
		return nil, twerrors.RequiredArgumentError("tool")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	toolIDs, err := r.toolService.ToolsIDsWithRenames(ctx, ts.ToToolName(req.Tool))
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	analysisIDs, err := r.alertService.LatestAnalysisIDsForRef(ctx, repoID, ts.LatestAnalysisFilter{
		Ref:     req.Ref,
		ToolIDs: toolIDs,
	})
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	analyses, err := r.alertService.FindFilesExtracted(ctx, repoID, analysisIDs)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	extractedFiles := transforms.Map(analyses, func(a *ts.Analysis) *ts.AnalysisExtractedFiles {
		return a.AnalysisExtractedFiles
	})

	total, languages := getToolStatusExtractedMap(extractedFiles)

	return &proto.FilesExtractedSummaryResponse{
		TotalExtracted:     total,
		LanguagesExtracted: languages,
	}, nil
}

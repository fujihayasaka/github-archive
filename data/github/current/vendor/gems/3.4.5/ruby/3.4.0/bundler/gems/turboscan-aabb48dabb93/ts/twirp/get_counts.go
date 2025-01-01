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

func (r *ResultsResolver) GetCounts(ctx context.Context, req *proto.CountsRequest) (*proto.CountsResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.ByteStrings("gh.turboscan.ref_names", req.RefNamesBytes),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}
	repo := ts.RepositoryEID(req.RepositoryId)

	filter := ts.AlertFilter{}
	filter.State = alertStateFromResolvedOnly(false)

	response := &proto.CountsResponse{}
	// This method should return false for AnalysisExists if no analyses exist for the
	// repo at all, not just no analyses matching the current filter.
	analysisFilterForRepo := ts.AnalysisFilter{
		RepositoryID:    repo,
		State:           ts.AnalysisStateFilterMostRecent,
		IncludeOutdated: true,
	}

	var err error
	response.AnalysisExists, err = r.alertService.AnalysisExists(ctx, analysisFilterForRepo)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// No need to fetch counts if we found no analysis.
	if !response.AnalysisExists {
		return response, nil
	}

	analysisFilter := ts.AnalysisFilter{
		RepositoryID:    repo,
		State:           ts.AnalysisStateFilterMostRecent,
		Refs:            req.RefNamesBytes,
		IncludeOutdated: true,
	}
	if req.ToolName != "" {
		names := []ts.ToolName{ts.ToToolName(req.ToolName)}
		toolIDs, err := r.toolService.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: names})
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
		if len(toolIDs) == 0 {
			return response, nil
		}

		analysisFilter.ToolIDs = toolIDs
	}

	createdAt, err := r.alertService.LatestAnalysisCreatedAt(ctx, analysisFilter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	response.LatestAnalysis = serializeTime(createdAt)

	response.OpenCount, err = r.alertService.Count(ctx, repo, filter, analysisFilter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return response, nil
}

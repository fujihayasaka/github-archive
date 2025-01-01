package twirp

import (
	"context"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
)

func (r *ResultsResolver) GetAnalyses(ctx context.Context, req *proto.AnalysesRequest) (*proto.AnalysesResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.ByteStrings("gh.turboscan.ref_names", req.RefNamesBytes),
		kvp.String("gh.turboscan.tool", req.Tool),
		kvp.String("gh.turboscan.sarif_id", req.SarifId),
		kvp.String("gh.turboscan.sort_order", req.SortOrder.String()),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}
	repositoryID := ts.RepositoryEID(req.RepositoryId)

	filter := ts.AnalysisFilter{
		RepositoryID:    repositoryID,
		Refs:            req.RefNamesBytes,
		IncludeOutdated: true,
	}

	sarifID, ok := ts.NewSarifID(req.SarifId)
	if !ok {
		return nil, twerrors.InvalidArgumentError("sarif_id", "invalid sarif_id")
	}
	if sarifID != "" {
		filter.SarifID = &sarifID
	}

	if req.Tool != "" {
		names := []ts.ToolName{ts.ToToolName(req.Tool)}
		toolIDs, err := r.toolService.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: names})
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
		if len(toolIDs) == 0 {
			return &proto.AnalysesResponse{Analyses: []*proto.Analysis{}, TotalCount: 0}, nil
		}
		filter.ToolIDs = toolIDs
	}

	pagination := tstypes.CreatePaginationInfo(req.Limit, req.NumericPage)

	findOptions := &ts.FindOptions{
		Preloads:   []string{"Tool", "ToolVersion"},
		Pagination: &pagination,
		SortBy:     getOrderBy(req.SortOrder),
	}

	analyses, err := r.alertService.FindAnalyses(ctx, filter, findOptions)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	count, err := r.alertService.CountAnalyses(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	failedIDs := transforms.FilterMap(analyses, func(a ts.Analysis) (ts.AnalysisID, bool) {
		return a.ID, a.Failed
	})
	processMsgs, err := r.alertService.ProcessErrors(ctx, repositoryID, failedIDs)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	deletableAnalyses, err := r.alertService.AreAnalysesDeletable(ctx, repositoryID, analyses)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	outAs := make([]*proto.Analysis, len(analyses))
	for idx, a := range analyses {
		outAs[idx] = serializeAnalysis(a, processMsgs[a.ID], deletableAnalyses[a.ID])
	}

	completeAnalysisExists, err := r.alertService.AnalysisExists(ctx, ts.AnalysisFilter{
		RepositoryID:    repositoryID,
		State:           ts.AnalysisStateFilterComplete,
		IncludeOutdated: true,
	})
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.AnalysesResponse{
		Analyses:               outAs,
		TotalCount:             count,
		CompleteAnalysisExists: completeAnalysisExists,
	}, nil
}

func getOrderBy(s proto.AnalysesSortOrder) string {
	if s == proto.AnalysesSortOrder_ANALYSES_CREATED_ASCENDING {
		return "ts_analyses.created_at asc, ts_analyses.id asc"
	}
	return "ts_analyses.created_at desc, ts_analyses.id desc"
}

package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetCountsByTool(ctx context.Context, req *proto.CountsByToolRequest) (*proto.CountsByToolResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.ByteStrings("gh.turboscan.ref_names", req.RefNamesBytes),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repo := ts.RepositoryEID(req.RepositoryId)
	filter := ts.AlertFilter{
		State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN,
	}

	analysisFilter := ts.AnalysisFilter{
		RepositoryID:    repo,
		Refs:            req.RefNamesBytes,
		State:           ts.AnalysisStateFilterMostRecent,
		IncludeOutdated: true,
	}

	// RefNames can be empty for uninitialised repositories. In that case, let's
	// just quickly return a 0 count and no tools. NOTE, this differs from the
	// semantics of other endpoints that treat an empty ref list as meaning "all
	// refs".
	if len(req.RefNamesBytes) == 0 {
		return &proto.CountsByToolResponse{}, nil
	}

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)
	counters, err := r.alertService.CountByTool(ctx, repo, filter, analysisFilter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.CountsByToolResponse{
		ToolCounts: serializeCounters(counters),
	}, nil
}

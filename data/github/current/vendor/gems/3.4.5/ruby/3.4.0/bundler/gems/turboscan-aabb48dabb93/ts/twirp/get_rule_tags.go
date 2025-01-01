package twirp

import (
	"context"
	"sort"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetRuleTags(ctx context.Context, req *proto.RuleTagsRequest) (*proto.RuleTagsResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received")

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repo := ts.RepositoryEID(req.RepositoryId)

	filter := ts.RuleTagFilter{RepoID: repo}

	if len(req.Tools) > 0 {
		names := transforms.Map(req.Tools, ts.ToToolName)
		toolIDs, err := r.toolService.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: names})
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
		if len(toolIDs) == 0 {
			return &proto.RuleTagsResponse{RuleTags: []string{}}, nil
		}
		filter.ToolIDs = toolIDs
	}

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)
	tags, err := r.alertService.RulesTags(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	sort.Strings(tags)

	return &proto.RuleTagsResponse{
		RuleTags: tags,
	}, nil
}

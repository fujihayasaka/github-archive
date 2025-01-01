package twirp

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

// ToolNames returns a de-duplicated list of all tool names ever used in analyses on the repository with the given ID
func (r *ResultsResolver) ToolNames(ctx context.Context, req *proto.ToolNamesRequest) (*proto.ToolNamesResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		ts.RepositoryEID(req.RepositoryId).AsKVP(),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)
	tools, err := r.toolService.ToolsUsed(ctx, repoID)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	toolsProto := serializeToolDescriptions(tools)
	return &proto.ToolNamesResponse{
		Tools: toolsProto,
	}, nil
}

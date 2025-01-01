package managed_analyses

import (
	"context"

	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/twitchtv/twirp"
)

func (r *Service) UpdateLanguages(ctx context.Context, req *proto.UpdateLanguagesRequest) (*proto.UpdateLanguagesResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	codeqlPacks := ts.CodeqlPacks(req.CodeqlPacks)

	appctx.Logger(ctx).Info("request received",
		kvp.Strings("gh.turboscan.languages_added", req.LanguagesAdded),
		kvp.Strings("gh.turboscan.languages_removed", req.LanguagesRemoved),
		codeqlPacks.AsKVP(),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if req.DefaultRef == nil {
		return nil, twerrors.RequiredArgumentError("default_ref")
	}

	workflowRunID, err := r.ma.UpdateRepoLanguages(ctx, ts.RepositoryEID(req.RepositoryId), req.SupportedLanguages, req.LanguagesAdded, req.LanguagesRemoved, req.DefaultRef, ts.OwnerEID(req.OwnerId), codeqlPacks)

	if errors.Is(err, ts.ErrNoChangeRequired) {
		return &proto.UpdateLanguagesResponse{WorkflowRunId: uint64(workflowRunID)}, nil
	}
	if errors.Is(err, ts.ErrCodeqlConfigNotFound) || errors.Is(err, ts.ErrCodeqlRepoNotFound) {
		return nil, o11y.RecordError(span, twerrors.NotFoundError(err.Error()))
	}
	if errors.Is(err, ts.ErrCodeqlConfigConflict) {
		return nil, o11y.RecordError(span, twerrors.NewError(twirp.AlreadyExists, ErrorMsgCodeqlConfigConflict))
	}
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	return &proto.UpdateLanguagesResponse{WorkflowRunId: uint64(workflowRunID)}, nil
}

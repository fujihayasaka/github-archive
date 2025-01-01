package managed_analyses

import (
	"context"

	"github.com/aws/smithy-go/ptr"

	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/twitchtv/twirp"
)

func (r *Service) Update(ctx context.Context, req *proto.UpdateRequest) (*proto.UpdateResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	codeqlPacks := ts.CodeqlPacks(req.CodeqlPacks)

	appctx.Logger(ctx).Info("request received",
		kvp.Strings("gh.turboscan.languages", req.Languages),
		codeqlPacks.AsKVP(),
		kvp.String("gh.turboscan.runner_type", req.RunnerType.String()),
		kvp.String("gh.turboscan.runner_label", req.RunnerLabel),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if req.GlobalActorId == "" {
		return nil, twerrors.RequiredArgumentError("global_actor_id")
	}

	if req.ActorLogin == "" {
		return nil, twerrors.RequiredArgumentError("actor_login")
	}

	querySuite, err := deserializeQuerySuite(req.QuerySuite)
	if errors.Is(err, errUnspecifiedValue) {
		querySuite = nil
	} else if err != nil {
		return nil, twerrors.InternalError("Failed to deserialize query suite")
	}

	threatModel, err := deserializeThreatModel(req.ThreatModel)
	if errors.Is(err, errUnspecifiedValue) {
		threatModel = nil
	} else if err != nil {
		return nil, twerrors.InternalError("Failed to deserialize threat model")
	}

	actor := &ts.ActorGRIDLogin{
		GRID:  ts.ActorGRID(req.GlobalActorId),
		Login: req.ActorLogin,
	}

	var runnerLabel *string
	switch req.RunnerType {
	case proto.UpdateRequest_RUNNER_TYPE_UNCHANGED:
		// use the runner label from their current settings
		runnerLabel = nil
	case proto.UpdateRequest_RUNNER_TYPE_STANDARD:
		// use default github runners
		runnerLabel = ptr.String("")
	case proto.UpdateRequest_RUNNER_TYPE_LABELED:
		// provide a runner label in the Actions workflow so launch runs the job on a specific (possibly self-hosted) runner
		if req.RunnerLabel == "" {
			return nil, twerrors.RequiredArgumentError("runner_label")
		}
		runnerLabel = ptr.String(req.RunnerLabel)
	}

	workflowRunID, err := r.ma.UpdateRepo(ctx,
		ts.RepositoryEID(req.RepositoryId),
		req.SupportedLanguages,
		deserializeLanguageList(req.SelectedLanguages),
		querySuite,
		threatModel,
		actor,
		req.DefaultRef,
		ts.OwnerEID(req.OwnerId),
		codeqlPacks,
		runnerLabel,
	)

	if err == nil {
		return &proto.UpdateResponse{WorkflowRunId: uint64(workflowRunID), Noop: false}, nil
	}
	if errors.Is(err, ts.ErrNoChangeRequired) {
		return &proto.UpdateResponse{WorkflowRunId: uint64(workflowRunID), Noop: true}, nil
	}
	if errors.Is(err, ts.ErrCodeqlConfigConflict) {
		return nil, o11y.RecordError(span, twerrors.NewError(twirp.AlreadyExists, ErrorMsgCodeqlConfigConflict))
	}
	return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
}

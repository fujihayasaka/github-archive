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
	"go.opentelemetry.io/otel/attribute"
)

func (r *Service) Update(ctx context.Context, req *proto.UpdateRequest) (*proto.UpdateResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	span.SetAttributes(attribute.Int("gh.repo.id", int(req.RepositoryId)))
	defer span.End()

	codeqlPacks := ts.CodeqlPacks(req.CodeqlPacks)

	appctx.Logger(ctx).Info("request received",
		ts.RepositoryEID(req.RepositoryId).AsKVP(),
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

	useRunnerLabel := flagFromRunnerType(req.RunnerType)

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
		useRunnerLabel,
		req.RunnerLabel,
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

func flagFromRunnerType(runnerType proto.UpdateRequest_RunnerType) *bool {
	switch runnerType {
	case proto.UpdateRequest_RUNNER_TYPE_UNCHANGED:
		return nil
	case proto.UpdateRequest_RUNNER_TYPE_STANDARD:
		return ptr.Bool(false)
	case proto.UpdateRequest_RUNNER_TYPE_LABELED:
		return ptr.Bool(true)
	}
	panic("unhandled case in enum switch")
}

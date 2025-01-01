package managed_analyses

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"
	"golang.org/x/exp/slices"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"go.opentelemetry.io/otel/attribute"
)

func (r *Service) Enable(ctx context.Context, req *proto.EnableRequest) (*proto.EnableResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	span.SetAttributes(attribute.Int("gh.repo.id", int(req.RepositoryId)))
	defer span.End()

	codeqlPacks := ts.CodeqlPacks(req.CodeqlPacks)

	appctx.Logger(ctx).Info("request received",
		ts.RepositoryEID(req.RepositoryId).AsKVP(),
		kvp.Strings("gh.turboscan.selected_languages", req.SelectedLanguages),
		kvp.Strings("gh.turboscan.supported_languages", req.SupportedLanguages),
		codeqlPacks.AsKVP(),
		kvp.Bool("gh.turboscan.use_code_scanning_runner_label", req.UseCodeScanningRunnerLabel),
		kvp.String("gh.turboscan.runner_label", req.RunnerLabel),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}
	repoID := ts.RepositoryEID(req.RepositoryId)

	if req.GlobalRepositoryId == "" {
		return nil, twerrors.RequiredArgumentError("global_repository_id")
	}

	if req.OwnerId == 0 {
		return nil, twerrors.RequiredArgumentError("owner_id")
	}
	ownerID := ts.OwnerEID(req.OwnerId)

	if req.EnabledByActorLogin == "" {
		return nil, twerrors.RequiredArgumentError("enabled_by_actor_login")
	}

	if req.EnabledByActorGrid == "" {
		return nil, twerrors.RequiredArgumentError("enabled_by_actor_grid")
	}

	for _, lang := range req.SelectedLanguages {
		if !slices.Contains(req.SupportedLanguages, lang) {
			return nil, twerrors.InvalidArgumentError("selected_languages", "All the selected languages should be present in supported_languages")
		}
	}

	querySuite, err := deserializeQuerySuite(req.QuerySuite)
	if errors.Is(err, errUnspecifiedValue) {
		return nil, twerrors.InvalidArgumentError("query_suite", "The query suite must be specified")
	} else if err != nil {
		return nil, twerrors.InternalError("Failed to deserialize query suite")
	}

	threatModel, err := deserializeThreatModel(req.ThreatModel)
	if errors.Is(err, errUnspecifiedValue) {
		return nil, twerrors.InvalidArgumentError("threat_model", "The threat model must be specified")
	} else if err != nil {
		return nil, twerrors.InternalError("Failed to deserialize threat model")
	}

	// Set ExtractionOptions
	// We do this here to avoid having to push this logic further down.
	// This also makes it possible to make this something that the client might
	// specify in the future.
	csharpExtractionOptions := ts.CSharpExtractionOptions_TRACED
	if !r.cSharpBuildlessDisabled {
		csharpExtractionOptions = ts.CSharpExtractionOptions_BUILDLESS
	}

	javaExtractionOption := ts.JavaExtractionOptions_TRACED
	if !r.javaBuildlessDisabled {
		javaExtractionOption = ts.JavaExtractionOptions_BUILDLESS
	}
	if req.HasKotlin {
		// Kotlin always requires traced extraction
		javaExtractionOption = ts.JavaExtractionOptions_TRACED
	}

	actor := &ts.ActorGRIDLogin{
		GRID:  ts.ActorGRID(req.EnabledByActorGrid),
		Login: req.EnabledByActorLogin,
	}

	workflowRunID, err := r.ma.EnableRepo(ctx,
		repoID,
		req.SupportedLanguages,
		req.SelectedLanguages,
		*querySuite,
		*threatModel,
		actor,
		ts.RepositoryGRID(req.GlobalRepositoryId),
		req.DefaultRef,
		ownerID,
		req.UseCodeScanningRunnerLabel,
		req.RunnerLabel,
		javaExtractionOption,
		csharpExtractionOptions,
		codeqlPacks,
	)

	if err != nil && !errors.Is(err, ts.ErrNoChangeRequired) {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	noop := errors.Is(err, ts.ErrNoChangeRequired)
	return &proto.EnableResponse{WorkflowRunId: uint64(workflowRunID), Noop: noop}, nil
}

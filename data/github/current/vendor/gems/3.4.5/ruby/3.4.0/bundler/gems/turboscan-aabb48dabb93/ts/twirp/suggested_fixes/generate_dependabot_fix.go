package suggested_fixes

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func (s *Service) GenerateDependabotFix(ctx context.Context, req *proto.GenerateDependabotFixRequest) (*proto.GenerateDependabotFixResponse, error) {

	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(
			attribute.Int("gh.request_id", int(req.RequestId)),
		),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.commit_oid", req.CommitOid),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if len(req.CommitOid) == 0 {
		return nil, twerrors.RequiredArgumentError("commit_oid")
	}

	if len(req.Sarif) == 0 {
		return nil, twerrors.RequiredArgumentError("sarif")
	}

	if len(req.FilePaths) == 0 {
		return nil, twerrors.RequiredArgumentError("file_paths")
	}

	job := jobs.GenerateDependabotFixJob{
		RequestId: req.RequestId,
		RepoID:    ts.RepositoryEID(req.RepositoryId),
		CommitOid: ts.Sha(req.CommitOid),
		Sarif:     req.Sarif,
		FilePaths: req.FilePaths,
	}

	_, err := s.aqueduct.PerformLater(ctx, job)
	if err != nil {
		return nil, err
	}

	return &proto.GenerateDependabotFixResponse{
		Success: true,
	}, nil
}

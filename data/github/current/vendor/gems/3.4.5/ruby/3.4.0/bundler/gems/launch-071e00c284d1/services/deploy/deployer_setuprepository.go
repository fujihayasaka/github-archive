package deploy

import (
	"context"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
)

type initializeProviderData struct {
	repoID      types.GlobalID
	ownerID     types.GlobalID
	planOwnerID types.GlobalID
	nwo         types.RepositoryFullName
}

func (s *service) SetupRepository(ctx context.Context, req *pb.SetupRepositoryRequest) (*pb.SetupRepositoryResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	data, err := s.extractAndValidateSetupRepositoryData(ctx, req)
	if err != nil {
		s.cfg.Log.Report(ctx, err)
		return nil, err
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", data.repoID.String()),
		kvp.String("gh.owner.global_id", data.ownerID.String()),
		kvp.String("gh.launch.plan_owner.global_id", data.planOwnerID.String()),
	)
	s.cfg.Log.Log(ctx, "setup repository request")

	err = s.cfg.Workers.Run(ctx, "setup-repository", func(jobCtx context.Context) error {
		jobCtx, span := tracing.StartWithOpFuncName(jobCtx, "SetupRepository")
		defer span.End()

		s.cfg.Log.Log(jobCtx, "setup repository request async")
		err := s.initializeProvider(jobCtx, data)
		if err != nil {
			s.cfg.Log.Report(jobCtx, err)
			return tracing.RecordError(span, err)
		}
		return nil
	})
	if err != nil {
		s.cfg.Log.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	return &pb.SetupRepositoryResponse{Status: "success"}, nil
}

func (s *service) extractAndValidateSetupRepositoryData(ctx context.Context, req *pb.SetupRepositoryRequest) (*initializeProviderData, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoID, err := s.GetGlobalIDFromIdentity(ctx, req.GetRepositoryId(), "SetupRepository")
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}
	if repoID.IsZeroValue() {
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("repo id cannot be nil"))
	}

	ownerID, err := s.GetGlobalIDFromIdentity(ctx, req.GetOwnerId(), "SetupRepository")
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}
	if ownerID.IsZeroValue() {
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
	}

	planOwnerID, err := s.GetGlobalIDFromIdentity(ctx, req.GetPlanOwnerId(), "SetupRepository")
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}
	if planOwnerID.IsZeroValue() {
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("plan owner id cannot be nil"))
	}

	ownerName := req.GetOwner()
	if ownerName == "" {
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("owner name cannot be nil"))
	}

	repoName := req.GetName()
	if repoName == "" {
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("repo name cannot be nil"))
	}

	nwo := types.RepositoryFullName{
		Owner: ownerName,
		Name:  repoName,
	}

	return &initializeProviderData{repoID, ownerID, planOwnerID, nwo}, nil
}

func (s *service) initializeProvider(ctx context.Context, data *initializeProviderData) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	startTime := time.Now()

	_, _, outcome, err := s.cfg.TenantHandler.GetOrCreateTenants(ctx, data.repoID, data.ownerID, data.planOwnerID, data.nwo)
	mw.TagStatsWith(ctx, reqmeta.Tags{
		"outcome": string(outcome),
		"context": "setup_repository",
	})

	duration := time.Since(startTime)
	s.cfg.Stats.LegacyTiming(ctx, "org_acquisition_time", statter.Tags{"outcome": string(outcome)}, duration)
	s.cfg.Log.Log(ctx, "org ", kvp.String("gh.launch.get_or_create_tenant.outcome", string(outcome)), kvp.Int64("gh.launch.tenant.acquisition_time_ms", int64(duration/time.Millisecond)))

	if err != nil {
		span.RecordError(err)
		return err
	}
	return nil
}

package deploy

import (
	"context"
	"fmt"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
)

func (s *service) SetupTenant(ctx context.Context, req *pb.SetupTenantRequest) (*pb.SetupTenantResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	globalID, err := s.GetGlobalIDFromIdentity(ctx, req.GetGlobalRelayId(), "SetupTenant")
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}
	if globalID.IsZeroValue() {
		err := tracing.RecordError(span, svcerr.NewInvalidArgumentError("global id cannot be nil"))
		s.cfg.Log.Report(ctx, err)
		return nil, err
	}

	ownerGlobalID, err := s.GetGlobalIDFromIdentity(ctx, req.GetOwnerGlobalRelayId(), "SetupTenant")
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.global_id", globalID.String()), kvp.String("gh.launch.owner.global_id", ownerGlobalID.String()))

	s.cfg.Log.Debug(ctx, "setup tenant request", kvp.Int64("gh.launch.timeout_ms", req.GetTimeoutMs()))

	success := make(chan bool, 2)

	var timeout <-chan time.Time
	if req.GetTimeoutMs() == 0 {
		// Push something onto the success channel already, as we are not going to wait for the worker to finish
		success <- true
	} else {
		timeout = time.After(time.Millisecond * time.Duration(req.GetTimeoutMs()))
	}

	err = s.cfg.Workers.Run(ctx, "setup-tenant", func(jobCtx context.Context) error {
		jobCtx, span := tracing.StartWithOpFuncName(jobCtx, "SetupTenant")
		defer span.End()

		s.cfg.Log.Debug(jobCtx, "setup tenant request async")
		err := s.initializeTenantProvider(jobCtx, globalID, ownerGlobalID, req.GetTimeoutMs())
		if err != nil {
			s.cfg.Log.Report(jobCtx, err)

			success <- false
			return tracing.RecordError(span, err)
		}

		success <- true
		return nil
	})
	if err != nil {
		s.cfg.Log.Report(ctx, err)
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}

	select {
	case success := <-success:
		if success {
			return &pb.SetupTenantResponse{Status: "success"}, nil
		}
		return nil, svcerr.NewInternalError("error setting up tenant")
	case <-timeout:
		return nil, svcerr.NewDeadlineExceededError("deadline of %d exceeded during tenant creation", req.GetTimeoutMs())
	}
}

func (s *service) initializeTenantProvider(ctx context.Context, globalID, ownerGlobalID types.GlobalID, timeout int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	startTime := time.Now()

	outcome, err := s.cfg.TenantHandler.GetOrCreateTenant(ctx, globalID, ownerGlobalID)
	mw.TagStatsWith(ctx, reqmeta.Tags{
		"outcome": string(outcome),
		"context": "setup_tenant",
	})

	duration := time.Since(startTime)
	s.cfg.Stats.LegacyTiming(ctx, "org_acquisition_time", statter.Tags{"outcome": string(outcome)}, duration)
	// The intent here is to record instances where successful tenant creation is successful but not within the timeout for the overall gRPC handler
	if outcome == deployer.OrgCreationSuccess && timeout > 0 {
		s.cfg.Stats.Counter(ctx, "setup_tenant.tenant_created", statter.Tags{"within_timout": fmt.Sprintf("%t", duration.Milliseconds() < timeout)}, 1)
	}
	s.cfg.Log.Log(ctx, "acquired tenant for entity", kvp.String("gh.launch.get_or_create_tenant.outcome", string(outcome)), kvp.Int64("gh.launch.tenant.acquisition_time_ms", int64(duration/time.Millisecond)))

	if err != nil {
		return tracing.RecordError(span, err)
	}
	switch outcome {
	case deployer.OrgCreationSuccess, deployer.OrgCreationUnnecessary:
		return nil
	default:
		return tracing.RecordError(span, errors.Errorf("Unsuccessful tenant creation, outcome: %s", outcome))
	}
}

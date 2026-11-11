package aqueduct

import (
	"context"
	"fmt"
	"strconv"
	"time"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	jobsproto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/trace"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/proto"
)

// Top-level handler function variables to allow for easier mocking in tests
var (
	handleDependabotSnapshotInitJob     = HandleDependabotSnapshotInitJob
	handleDependabotSnapshotPostPushJob = HandleDependabotSnapshotPostReceiveJob
	handleUpdateGraphComputeUsageJob    = HandleUpdateGraphComputeUsageJob
	handleExcludeCanonicalSnapshotsJob  = HandleExcludeCanonicalSnapshotsJob
	echoHandlerFactory                  = NewEchoHandler
)

type JobHandler struct {
	cfg                *config.Config
	logger             log.Logger
	statter            stats.Client
	tracer             *trace.Tracer
	gitClient          gitaccess.Client
	publisher          hydro.Publisher
	ffClient           features.Client
	snapshotsSvc       interfaces.SnapshotsService
	dependabotEventSvc interfaces.DependabotEventService
	HandlerFn          aq.JobHandler
}

// NewDSAPIJobHandler routes Aqueduct jobs to the appropriate Dependabot handlers.
func NewDSAPIJobHandler(
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
	tracer *trace.Tracer,
	gitClient gitaccess.Client,
	publisher hydro.Publisher,
	ffClient features.Client,
	snapshotsSvc interfaces.SnapshotsService,
	dependabotEventSvc interfaces.DependabotEventService,
) *JobHandler {
	h := &JobHandler{
		cfg:                cfg,
		logger:             logger,
		statter:            statter,
		tracer:             tracer,
		gitClient:          gitClient,
		publisher:          publisher,
		ffClient:           ffClient,
		snapshotsSvc:       snapshotsSvc,
		dependabotEventSvc: dependabotEventSvc,
	}

	h.HandlerFn = func(ctx context.Context, rr aq.ReceiveResult) error {
		if ctx.Err() != nil {
			return ctx.Err()
		}

		ctx = proximaContext(ctx, rr)

		ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "HandleJob", rr.Queue)
		defer ender()

		tags := stats.Tags{
			"queue": rr.Queue,
			"valid": strconv.FormatBool(rr.ValidPayload),
		}

		// Record latency from job creation to handling
		statter.DistributionMs("aqueduct.handler.latency", tags, time.Since(rr.SentAt))

		execStartTime := time.Now()
		err := h.handleJobInternal(ctx, rr)
		execDuration := time.Since(execStartTime)

		// Record execution time for the job handler
		statter.DistributionMs("aqueduct.handler.elapsed_ms", tags.Merge(stats.Tags{
			"completed_with_error": strconv.FormatBool(err != nil),
		}), execDuration)

		if err != nil {
			logger.WithError(err).Error(
				"Aqueduct handler execution error",
				semconv.AqueductExecutionTimeMs(execDuration.Milliseconds()),
				semconv.AqueductHandlerQueue(rr.Queue))
		} else {
			logger.Info("Aqueduct handler execution success",
				semconv.AqueductExecutionTimeMs(execDuration.Milliseconds()),
				semconv.AqueductHandlerQueue(rr.Queue))
		}

		return err
	}

	return h
}

func (h *JobHandler) handleJobInternal(ctx context.Context, j aq.ReceiveResult) error {
	switch j.Queue {
	case DependabotSnapshotInitQueue:
		job := &jobsproto.DependabotSnapshotInitJob{}
		if err := proto.Unmarshal(j.Payload, job); err != nil {
			h.statter.Counter("aqueduct.handler.error", stats.Tags{"reason": "unmarshal", "queue": j.Queue}, 1)
			return fmt.Errorf("unmarshal init job: %w", err)
		}
		return handleDependabotSnapshotInitJob(ctx, h.cfg, h.logger, h.statter, h.tracer, h.gitClient, h.publisher, h.ffClient, h.dependabotEventSvc, job)

	case DependabotSnapshotPostPushQueue:
		job := &jobsproto.DependabotSnapshotPostPushJob{}
		if err := proto.Unmarshal(j.Payload, job); err != nil {
			h.statter.Counter("aqueduct.handler.error", stats.Tags{"reason": "unmarshal", "queue": j.Queue}, 1)
			return fmt.Errorf("unmarshal post-push job: %w", err)
		}
		return handleDependabotSnapshotPostPushJob(ctx, h.cfg, h.logger, h.statter, h.tracer, h.gitClient, h.publisher, h.ffClient, h.dependabotEventSvc, job)

	case UpdateGraphComputeUsageQueue:
		job := &jobsproto.UpdateGraphComputeUsageJob{}
		if err := proto.Unmarshal(j.Payload, job); err != nil {
			h.statter.Counter("aqueduct.handler.error", stats.Tags{"reason": "unmarshal", "queue": j.Queue}, 1)
			return fmt.Errorf("unmarshal update-graph compute usage job: %w", err)
		}
		return handleUpdateGraphComputeUsageJob(ctx, h.cfg, h.logger, h.statter, job)

	case ExcludeCanonicalSnapshotsQueue:
		job := &jobsproto.ExcludeCanonicalSnapshotsJob{}
		if err := proto.Unmarshal(j.Payload, job); err != nil {
			h.statter.Counter("aqueduct.handler.error", stats.Tags{"reason": "unmarshal", "queue": j.Queue}, 1)
			return fmt.Errorf("unmarshal exclude canonical snapshots job: %w", err)
		}
		return handleExcludeCanonicalSnapshotsJob(ctx, h.cfg, h.logger, h.statter, h.snapshotsSvc, job)

	case EchoQueue, h.cfg.AqueductEchoQueue:
		// Preserve echo behavior
		return echoHandlerFactory(h.logger)(ctx, j)

	default:
		h.statter.Counter("aqueduct.handler.error", stats.Tags{"reason": "unknown_queue", "queue": j.Queue}, 1)
		return fmt.Errorf("unknown queue %s", j.Queue)
	}
}

func proximaContext(ctx context.Context, rr aq.ReceiveResult) context.Context {
	if rr.Headers != nil {
		if v, ok := rr.Headers[headers.Tenant]; ok {
			ctx = tenant.TenantContext(ctx, v)
		}
		if v, ok := rr.Headers[headers.TenantID]; ok {
			ctx = tenant.TenantIDContext(ctx, v)
		}
	}
	return ctx
}

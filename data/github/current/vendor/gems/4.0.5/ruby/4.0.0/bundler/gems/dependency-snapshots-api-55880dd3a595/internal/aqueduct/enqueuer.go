package aqueduct

import (
	"context"
	"fmt"

	"github.com/avast/retry-go/v4"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/proto"
)

const (
	EchoQueue                       = "echo"
	ExcludeCanonicalSnapshotsQueue  = "exclude-canonical-snapshots"
	DependabotSnapshotPostPushQueue = "dependabot-snapshot-post-push"
	DependabotSnapshotInitQueue     = "dependabot-snapshot-init"
	UpdateGraphComputeUsageQueue    = "update-graph-compute-usage"
	DenormalizeSnapshotDepsQueue    = "denormalize-snapshot-deps"
)

// QueueForJob returns the default queue name for the given job type.
func QueueForJob(j proto.Message) (string, error) {
	switch j.(type) {
	case *jobs.EchoJob:
		return EchoQueue, nil
	case *jobs.ExcludeCanonicalSnapshotsJob:
		return ExcludeCanonicalSnapshotsQueue, nil
	case *jobs.DependabotSnapshotInitJob:
		return DependabotSnapshotInitQueue, nil
	case *jobs.DependabotSnapshotPostPushJob:
		return DependabotSnapshotPostPushQueue, nil
	case *jobs.UpdateGraphComputeUsageJob:
		return UpdateGraphComputeUsageQueue, nil
	case *jobs.DenormalizeSnapshotDependenciesJob:
		return DenormalizeSnapshotDepsQueue, nil
	}
	return "", fmt.Errorf("unknown job type %T", j)
}

// JobForQueue returns a new job instance for the given queue name.
func JobForQueue(queue string) (proto.Message, error) {
	switch queue {
	case EchoQueue:
		return &jobs.EchoJob{}, nil
	case ExcludeCanonicalSnapshotsQueue:
		return &jobs.ExcludeCanonicalSnapshotsJob{}, nil
	case DependabotSnapshotInitQueue:
		return &jobs.DependabotSnapshotInitJob{}, nil
	case DependabotSnapshotPostPushQueue:
		return &jobs.DependabotSnapshotPostPushJob{}, nil
	case UpdateGraphComputeUsageQueue:
		return &jobs.UpdateGraphComputeUsageJob{}, nil
	case DenormalizeSnapshotDepsQueue:
		return &jobs.DenormalizeSnapshotDependenciesJob{}, nil
	}
	return nil, fmt.Errorf("unknown queue %s", queue)
}

// Enqueuer is an interface for enqueuing jobs.
type Enqueuer interface {
	Enqueue(ctx context.Context, j proto.Message) (string, error)
	EnqueueWithRoute(ctx context.Context, j proto.Message, queue string) (string, error)
}

// JobEnqueuer is an implementation of Enqueuer that uses Aqueduct to enqueue jobs.
type JobEnqueuer struct {
	config         *config.Config
	statter        stats.Client
	aqueductClient aqueduct.Client
	retryOpts      []retry.Option
}

// NewJobEnqueuer creates a new JobEnqueuer.
func NewJobEnqueuer(cfg *config.Config, ac aqueduct.Client, st stats.Client, retryOpts ...retry.Option) *JobEnqueuer {
	return &JobEnqueuer{
		config:         cfg,
		statter:        st,
		aqueductClient: ac,
		retryOpts:      retryOpts,
	}
}

// Enqueue given job to it's "default queue" based job's type.
// This method doesn't support routing a particular job type to >1 queue!
// When creating backfill-scoped queues/worker pools, use EnqueueWithRoute.
func (je *JobEnqueuer) Enqueue(ctx context.Context, j proto.Message) (string, error) {
	queue, err := QueueForJob(j)
	if err != nil {
		return "", fmt.Errorf("failed to determine queue for job: %w", err)
	}

	return je.EnqueueWithRoute(ctx, j, queue)
}

// EnqueueWithRoute enqueues the given job routed to the given queue name. Use this ONLY when
// a manual queue override is appropriate (backfill scenario etc.)
func (je *JobEnqueuer) EnqueueWithRoute(ctx context.Context, j proto.Message, queue string) (string, error) {
	bytes, err := proto.Marshal(j)
	if err != nil {
		je.statter.Counter("aqueduct.enqueuer.failed", stats.Tags{
			"reason": "marshal_job",
			"queue":  queue,
		}, 1)
		return "", fmt.Errorf("failed to marshal job: %w", err)
	}

	aj := aqueduct.Job{
		App:     je.config.AqueductAppName,
		Queue:   queue,
		Payload: bytes,
		Headers: map[string]string{},
	}

	// Get the tenant name as a url slug, e.g. 'test-prodweu01'
	if tenantSlug := tenant.GetTenant(ctx); tenantSlug != "" {
		aj.Headers[headers.Tenant] = tenantSlug
	}

	// Get the integer id of the tenant, if available
	if tenantID := tenant.GetTenantID(ctx); tenantID != "" {
		aj.Headers[headers.TenantID] = tenantID
	}

	opts := []retry.Option{retry.Context(ctx)}
	if len(je.retryOpts) > 0 {
		opts = append(opts, je.retryOpts...)
	}
	jobID, err := retry.DoWithData(func() (string, error) {
		return je.aqueductClient.Send(ctx, aj)
	}, opts...)
	if err != nil {
		je.statter.Counter("aqueduct.enqueuer.failed", stats.Tags{
			"reason": "aqueduct_send",
			"queue":  queue,
		}, 1)
		return "", fmt.Errorf("failed to enqueue job: %w", err)
	}

	return jobID, nil
}

// NoopEnqueuer is an enqueuer that does nothing.
type NoopEnqueuer struct{}

// NewNoopEnqueuer creates a new NoopEnqueuer.
func NewNoopEnqueuer() *NoopEnqueuer {
	return &NoopEnqueuer{}
}

// Enqueue does nothing and returns empty string and nil error.
func (p *NoopEnqueuer) Enqueue(ctx context.Context, j proto.Message) (string, error) {
	return "", nil
}

// EnqueueWithRoute does nothing and returns empty string and nil error.
func (p *NoopEnqueuer) EnqueueWithRoute(ctx context.Context, j proto.Message, queue string) (string, error) {
	return "", nil
}

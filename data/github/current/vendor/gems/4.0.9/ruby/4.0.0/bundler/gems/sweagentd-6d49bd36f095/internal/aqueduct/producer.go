package aqueduct

import (
	"context"
	"fmt"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
)

var zero = time.Time{}

// QueueJob queues an (aqueduct) job for later processing.
func (ac *Client) QueueJob(ctx context.Context, job sweagentd.AqueductJob) (string, error) {
	id, err := ac.queueJob(ctx, job, zero)
	if err != nil {
		return "", goerrors.Errorf("failed to queue job: %w", err)
	}
	return id, nil
}

// ScheduleJob schedules a job for processing at a specific time.
// If deliverAt is zero, it defaults to immediate processing.
func (ac *Client) ScheduleJob(ctx context.Context, job sweagentd.AqueductJob, deliverAt time.Time) (string, error) {
	id, err := ac.queueJob(ctx, job, deliverAt)
	if err != nil {
		return "", goerrors.Errorf("failed to schedule job: %w", err)
	}
	return id, nil
}

// RequeueJob requeues a job for later processing using the default redelivery delay.
func (ac *Client) RequeueJob(ctx context.Context, job sweagentd.AqueductJob) (string, error) {
	return ac.RequeueJobWithDelay(ctx, job, time.Duration(ac.defaultRedeliveryDelaySeconds)*time.Second)
}

// RequeueJobWithDelay requeues a job with an optional redelivery delay.
// If delay is negative, [Client.defaultRedeliveryDelaySeconds] is used.
// If delay is zero, no delay is applied.
func (ac *Client) RequeueJobWithDelay(ctx context.Context, job sweagentd.AqueductJob, delay time.Duration) (string, error) {
	if delay < 0 {
		delay = time.Duration(ac.defaultRedeliveryDelaySeconds) * time.Second
	}

	deliverAt := time.Now().Add(delay)

	// Track the number of times the job has been requeued.
	requeueCount := max(job.GetRequeueCount(), 0)
	job.SetRequeueCount(requeueCount + 1)

	ac.obsv.Statter.Counter("aqueduct.client.requeue_received_job", ac.obsv.TelemetryTags(ctx), 1)
	ac.obsv.Statter.DistributionMs("aqueduct.client.requeue_received_job_delay", ac.obsv.TelemetryTags(ctx), delay)

	id, err := ac.queueJob(ctx, job, deliverAt)
	if err != nil {
		return "", goerrors.Errorf("failed to requeue job: %w", err)
	}
	return id, nil
}

func (ac *Client) queueJob(ctx context.Context, job sweagentd.AqueductJob, deliverAt time.Time, opts ...aqueduct.SendOption) (string, error) {
	// serialize the job payload
	payload, err := job.Marshal()
	if err != nil {
		return "", goerrors.Errorf("failed to marshal job payload: %w", err)
	}

	// set headers and such
	aqueductJob := &aqueduct.Job{
		App:     ac.appName,
		Queue:   job.QueueName(),
		Payload: payload,
		Headers: getJobHeaders(ctx, job),
	}

	if !deliverAt.IsZero() {
		aqueductJob.DeliverAt = deliverAt
	}

	id, err := ac.client.Send(ctx, *aqueductJob, opts...)
	if err != nil {
		return "", goerrors.Errorf("failed to send job to aqueduct: %w", err)
	}

	jobs.AddQueuedJobToRequestContext(ctx, ac.obsv, job, aqueductJob, id)

	return id, nil
}

func getJobHeaders(ctx context.Context, job sweagentd.AqueductJob) map[string]string {
	headers := getTenantHeaders(ctx)
	headers[jobs.RequeueCountHeader] = fmt.Sprintf("%d", job.GetRequeueCount())
	headers[jobs.RequeueMaxCountHeader] = fmt.Sprintf("%d", job.MaxRequeueCount())
	jobs.InjectTraceContext(ctx, headers)
	return headers
}

func getTenantHeaders(ctx context.Context) map[string]string {
	headers := make(map[string]string)
	if tenantSlug := requestctx.TenantSlug(ctx); tenantSlug != "" {
		headers[requestctx.GitHubTenantHeader] = tenantSlug
	}
	if tenantID := requestctx.TenantID(ctx); tenantID != "" {
		headers[requestctx.GitHubTenantIDHeader] = tenantID
	}
	return headers
}

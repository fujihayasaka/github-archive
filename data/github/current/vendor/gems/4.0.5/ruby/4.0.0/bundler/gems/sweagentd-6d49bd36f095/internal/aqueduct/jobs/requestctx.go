package jobs

import (
	"context"
	"strconv"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
)

// RequeueCountHeader is the header used to indicate how many times a job has been requeued.
const RequeueCountHeader = "X-GITHUB-JOB-REQUEUE-COUNT"

// RequeueMaxCountHeader is the header used to indicate the maximum number of times a job can be requeued.
const RequeueMaxCountHeader = "X-GITHUB-JOB-MAX-REQUEUE-COUNT"

// AddQueuedJobToRequestContext adds job information to the request context.
func AddQueuedJobToRequestContext(ctx context.Context, obsv observability.Exporters, job sweagentd.AqueductJob, aqueductJob *aqueduct.Job, jobID string) {
	err := requestctx.AddAqueductJob(ctx, &requestctx.CtxAqueductJob{
		ID:           jobID,
		Queue:        aqueductJob.Queue,
		RequeueCount: job.GetRequeueCount(),
	})
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to add aqueduct job to request context")
	}
}

// AddReceivedJobToRequestContext adds received job information to the request context.
func AddReceivedJobToRequestContext(ctx context.Context, obsv observability.Exporters, rr aqueduct.ReceiveResult) error {
	err := ForwardTenantInformation(ctx, rr.Headers)
	if err != nil {
		return goerrors.Errorf("failed to forward tenant information: %w", err)
	}

	var requeueCount int32
	if val, ok := rr.Headers[RequeueCountHeader]; ok {
		i, err := strconv.ParseInt(val, 10, 32)
		if err == nil {
			requeueCount = int32(i)
		}
	}

	err = requestctx.AddAqueductJob(ctx, &requestctx.CtxAqueductJob{
		ID:                  rr.ID,
		Queue:               rr.Queue,
		DeliveryAttempt:     rr.DeliveryAttempt,
		MaxDeliveryAttempts: rr.MaxDeliveryAttempts,
		SentAt:              rr.SentAt,
		RequeueCount:        requeueCount,
	})
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to add aqueduct job to request context")
	}

	return nil
}

// ForwardTenantInformation extracts tenant information from headers and adds it to the request context.
func ForwardTenantInformation(ctx context.Context, headers map[string]string) error {
	val, ok := headers[requestctx.GitHubTenantHeader]
	if ok {
		err := requestctx.AddTenantSlug(ctx, val)
		if err != nil {
			return goerrors.Errorf("failed to add tenant slug to request context: %w", err)
		}
	}

	val, ok = headers[requestctx.GitHubTenantIDHeader]
	if ok {
		err := requestctx.AddTenantID(ctx, val)
		if err != nil {
			return goerrors.Errorf("failed to add tenant id to request context: %w", err)
		}
	}

	return nil
}

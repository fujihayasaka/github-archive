package azpclient

import (
	"context"
	"net/http"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

type ChecksService struct {
	client *Client
	http   *httpclient.Client
}

func (c *ChecksService) StepsFromChangeID(ctx context.Context, changeID int64, jobID string, planID string) ([]*azp.ChangeIDResponseSteps, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "checks.stepsfromchangeid"

	var resp *azp.ChangeIDResponse
	err := c.http.Do(
		ctx,
		opname,
		http.MethodGet,
		c.client.url.getStepsFromChangeIDURL(jobID, planID, changeID),
		nil,
		&resp,
		c.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Steps, nil
}

func (c *ChecksService) StepsFromChangeIDForRun(ctx context.Context, changeID int64, planID string, onlyInProgressJobs bool) ([]*azp.ChangeIDResponseJobSteps, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "checks.jobstepsfromchangeid"

	var resp *azp.ChangeIDResponseForRun
	err := c.http.Do(
		ctx,
		opname,
		http.MethodGet,
		c.client.url.getJobStepsFromChangeIDURL(planID, changeID, onlyInProgressJobs),
		nil,
		&resp,
		c.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Jobs, nil
}

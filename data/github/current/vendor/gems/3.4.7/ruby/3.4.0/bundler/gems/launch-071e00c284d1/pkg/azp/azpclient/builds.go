package azpclient

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	parser "github.com/github/actions-workflow-parser/go"
	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	runservice "github.com/github/actions-proto/gen/go/run-service/api/twirp/v1"

	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
	"github.com/github/launch/workflowbuild/build"
)

type BuildsService struct {
	client *Client
	http   *httpclient.Client
}

func (b *BuildsService) GetRunTenantInfo() *runservice.TenantInfo {
	return &runservice.TenantInfo{
		Id: b.client.url.tenantID,
		Urls: map[string]string{
			"CacheService":     b.client.url.getCacheServiceURL(),
			"PipelinesService": b.client.url.getPipelineServiceURL(),
		},
	}
}

func (b *BuildsService) Queue(ctx context.Context, wfb *build.WorkflowBuild, receiverURL string, resultsReceiverURL string, secretSource string, secretsUnencrypted map[string]string, variables map[string]string, wft *parser.WorkflowTemplate, concurrency *parser.ConcurrencySetting, featureFlags map[string]bool, appEnv launchconfig.AppEnv) (*azp.Build, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "build.queue"

	body, err := azp.NewBuildPayload(wfb, receiverURL, resultsReceiverURL, secretSource, secretsUnencrypted, variables, wft, concurrency, featureFlags, appEnv)
	if err != nil {
		return nil, err
	}

	// We use the `ExecutionID` in the E2E and OrchestrationID correlation headers in addition to the payload.
	// (See https://github.com/github/pe-actions-experience/issues/1949 and https://github.com/github/pe-actions-experience/issues/1840)
	ctx = azpcorrelation.WithVSSCorrelationID(ctx, wfb.ExecutionID.String())
	ctx = azpcorrelation.WithVSSOrchestrationID(ctx, wfb.ExecutionID.String())

	var resp *azp.Build
	err = b.http.Do(
		ctx,
		opname,
		http.MethodPost,
		b.client.url.getQueueBuildURL(),
		body.Content.Bytes(), // body needs special handling
		&resp,
		b.client.withDefaultOpts(
			ctx,
			WithMultipartPayload(body)...,
		)...)

	if err != nil {
		customerFacingErr := &azperrors.AZPSyntaxError{}
		if !errors.As(err, &customerFacingErr) {
			err = errors.Wrap(err, "failed to queue build")
		}
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (b *BuildsService) RunInfo(ctx context.Context, id types.WorkflowExecutionID) (*azp.RunInfoResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runinfo.get"

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.workflow.execution.id", id.String()))

	var resp *azp.RunInfoResponse
	err := b.http.Do(
		ctx,
		opname,
		http.MethodGet,
		b.client.url.getRunInfoURL(id),
		nil,
		&resp,
		b.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (b *BuildsService) Cancel(ctx context.Context, workflowRunID string, opts *azp.CancelOptions) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "build.cancel"

	type cancelBuildRequest struct {
		State      string `json:"state"`
		CanceledBy string `json:"canceledBy,omitempty"`
		Force      bool   `json:"force,omitempty"`
	}

	body := &cancelBuildRequest{
		State: "canceling",
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.workflow_build.id", workflowRunID))
	if opts != nil && opts.ActorName != nil {
		body.CanceledBy = *opts.ActorName
		body.Force = opts.Force
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.actor.name", *opts.ActorName), kvp.Bool("gh.launch.cancel_event.forced", opts.Force))
	}

	err := b.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		b.client.url.getBuildURL(workflowRunID),
		body,
		nil,
		b.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONContentType()))..., // server rejects json patch content type
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (b *BuildsService) DeleteLogs(ctx context.Context, workflowRunID string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "build.deletelogs"

	if strings.TrimSpace(workflowRunID) == "" {
		return fmt.Errorf("the workflow run id cannot be empty")
	}

	err := b.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		b.client.url.getDeleteBuildLogsURL(workflowRunID),
		nil,
		nil,
		b.client.withDefaultOpts(
			ctx,
			httpclient.WithValidator(func(r *http.Response) (retryable bool, err error) {
				if r.StatusCode == http.StatusNotFound {
					// don't treat 404 as error
					return false, nil
				}

				return azp.ResponseValidator()(r)
			}),
		)...,
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (b *BuildsService) DeleteLogsByPlanID(ctx context.Context, planID string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "build.deletelogs"

	if strings.TrimSpace(planID) == "" {
		return fmt.Errorf("the plan id cannot be empty")
	}

	err := b.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		b.client.url.getDeleteBuildLogsURLByPlanID(planID),
		nil,
		nil,
		b.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (b *BuildsService) ReportAdminEvent(ctx context.Context, name string, data map[string]string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "actions.report_admin_event"

	type adminEventRequest struct {
		Name string            `json:"name"`
		Data map[string]string `json:"data"`
	}

	body := &adminEventRequest{
		Name: name,
		Data: data,
	}

	err := b.http.Do(
		ctx,
		opname,
		http.MethodPost,
		b.client.url.getReportAdminEventsURL(),
		body,
		nil,
		b.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONContentType()))...,
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

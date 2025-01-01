package build

import (
	"context"
	"encoding/json"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"

	customerlabels "github.com/github/launch/config/customerlabels"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/utils/ghtenant"
)

// Processor processes invocation jobs from an Aqueduct queue
type Processor struct {
	workflowInvoker workflowinvoker.Invoker
	sloReporter     *slometrics.Reporter
	labeler         customerlabels.CustomerLabeler
	isMultiTenant   bool
}

// New returns a new build processor
func New(workflowInvoker workflowinvoker.Invoker, reporter *slometrics.Reporter, labeler customerlabels.CustomerLabeler, isMultiTenant bool) *Processor {
	return &Processor{
		workflowInvoker: workflowInvoker,
		sloReporter:     reporter,
		labeler:         labeler,
		isMultiTenant:   isMultiTenant,
	}
}

// Process takes a build.Job encoded as JSON in the payload and invokes it.
func (p *Processor) Process(ctx context.Context, obs *observability.Observability, jobPayload []byte, isFinalAttempt bool) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var job Job
	err := json.Unmarshal(jobPayload, &job)
	if err != nil {
		return errors.Wrap(err, "could not parse build job json payload")
	}

	obs.Debug(ctx, "aqueduct build job payload decoded",
		kvp.String("event", job.Invocation.Event.Name),
	)

	if err := job.Invocation.Target.GitHubTenant.Validate(p.isMultiTenant); err != nil {
		return errors.Wrap(err, "invalid github tenant")
	}

	// log proxima tenant information
	if p.isMultiTenant {
		ctx = ctxstash.WithFields(ctx,
			kvp.String("gh.tenant.slug", job.Invocation.Target.GitHubTenant.Slug),
			kvp.Int64("gh.tenant.id", job.Invocation.Target.GitHubTenant.ID),
		)
	}

	// the github tenant id still needs to be set in the context so it can be used for scheduled workflow syncs
	// this will be removed once the sync code is refactored to explicitly require the github tenant id
	// See: https://github.com/github/actions-core-enterprise/issues/779
	ctx, err = ghtenant.ContextWithTenantID(ctx, job.Invocation.Target.GitHubTenant.ID, p.isMultiTenant)
	if err != nil {
		return errors.Wrap(err, "error setting github tenant in current context")
	}

	ctx, err = ghtenant.ContextWithTenantSlug(ctx, job.Invocation.Target.GitHubTenant.Slug, p.isMultiTenant)
	if err != nil {
		return errors.Wrap(err, "error setting github tenant slug in current context")
	}

	span.SetAttributes(attribute.String("gh.launch.event.name", job.Invocation.Event.Name))
	ctx = ctxstash.WithFields(ctx, kvp.String("event", job.Invocation.Event.Name))
	obs.Counter(ctx, "build.processor.event_type", statter.Tags{"event_type": job.Invocation.Event.Name}, 1)

	// Start already called ReportQueueRunError if appropriate.
	return p.workflowInvoker.Start(ctx, obs, job.Invocation, isFinalAttempt, p.labeler)
}

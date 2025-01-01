package webhook

import (
	"bytes"
	"context"
	"encoding/json"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/google/go-github/v25/github"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"

	"github.com/github/launch/clients/ghtwirp"
	ghclient "github.com/github/launch/clients/github"
	"github.com/github/launch/config/customerlabels"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	hydro_schemas_github_actions_v0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/callcounter"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/globalidmigration"
	"github.com/github/launch/pkg/panicmultierrgroup"
	"github.com/github/launch/pkg/rate"
	"github.com/github/launch/pkg/schedulemanager"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/deploy/deliveryguid"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/haswaitedforrep"
)

// Config data needed to instantiate a Processor
type Config struct {
	AppID             int64
	ActionsBotNodeIDs []types.GlobalID
	ActionsAppIDs     []int64
	IsEnterprise      bool
	IsMultiTenant     bool
}

// Processor takes a webhook aqueduct payload and does the work to get a queued build (if required)
type Processor struct {
	cfg                *Config
	workflowInvoker    workflowinvoker.Invoker
	wbRepo             deployer.WorkflowBuildsRepository
	scheduleMngr       schedulemanager.Manager
	ghtwirp            ghtwirp.Client
	rptr               adminevents.Reporter
	sloReporter        *slometrics.Reporter
	labeler            customerlabels.CustomerLabeler
	webhookRateLimiter rate.RateLimiter
}

// New returns a new webhook.Processor
func New(cfg *Config, invoker workflowinvoker.Invoker, workflowBuildsRepo deployer.WorkflowBuildsRepository, sch schedulemanager.Manager, ghtwirp ghtwirp.Client, adminEventReporter adminevents.Reporter, sloReporter *slometrics.Reporter, labeler customerlabels.CustomerLabeler, webhookRateLimiter rate.RateLimiter) *Processor {
	return &Processor{
		cfg:                cfg,
		workflowInvoker:    invoker,
		wbRepo:             workflowBuildsRepo,
		scheduleMngr:       sch,
		ghtwirp:            ghtwirp,
		rptr:               adminEventReporter,
		sloReporter:        sloReporter,
		labeler:            labeler,
		webhookRateLimiter: webhookRateLimiter,
	}
}

// Process is the main entrypoint to running this Processor with an aqueduct Job.
// It is called from the queueworker.
func (p *Processor) Process(ctx context.Context, obs *observability.Observability, jobPayload []byte, isFinalAttempt bool) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var job Job
	err := json.Unmarshal(jobPayload, &job)
	if err != nil {
		obs.Counter(ctx, "queue.worker.process_job", statter.Tags{"status": "failed-decoding"}, 1)
		return errors.Wrap(err, "could not parse webhook job json payload")
	}

	ctx = deliveryguid.WithDeliveryGUID(ctx, &job.WebhookDeliveryID)

	ctx = appcontext.SetRequestID(ctx, job.GitHubRequestID)
	obs.Debug(ctx, "aqueduct job payload decoded",
		kvp.String("gh.launch.event.name", job.Event),
		kvp.Time("gh.launch.queued_at", job.EnqueuedAtTime()),
	)

	ctx = callcounter.WithCounter(ctx, "webhooks.processor.handleEvent")

	// The hasWaitedForRep key needs to be set in context to signal to the GraphQL client that replication
	// lag has been accounted for. Webhook events wait for replication and we want to pass that fact along
	// to the GraphQL server. This is important so that we can optimize DB usage by reading from replicas.
	ctx = haswaitedforrep.ContextWithHasWaitedForReplicas(ctx)

	// ------
	// Start with what's done in receiverService.handleWebhook
	// ------
	span.SetAttributes(attribute.String("gh.launch.event.name", job.Event))

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.event.name", job.Event))
	obs.Counter(ctx, "queue.worker.event_type", statter.Tags{"event_type": job.Event}, 1)

	// Skipping payload validation which receiver does here, we are trusting the queue info.

	// ------
	// Now we are duplicating some of receiverService.processWebhook
	// ------
	if job.Event == "ping" {
		return nil
	}

	if job.Event == "" {
		err := errors.New("missing event from job")
		obs.Report(ctx, err)
		return tracing.RecordError(span, err)
	}

	// Capture sanitized payload prior to replacing any global ids, as we want the original values to be present
	// in the data we persist to launch db. This ensures we don't replace ids in user visible data.
	sanitizedPayload, err := sanitizePayload(*job.RawPayload)
	if err != nil {
		return errors.Wrap(err, "failed to sanitize payload")
	}

	// Update any legacy global IDs in the job payload to the Next Global ID format
	newPayload, err := globalidmigration.ConvertPayloadIDs(ctx, obs, p.ghtwirp,
		"webhook.processor.process", *job.RawPayload)
	if err != nil {
		obs.Report(ctx, errors.Wrap(err, "error encountered while trying to convert job payload global IDs"))
	} else {
		*job.RawPayload = newPayload
	}

	// Parse the event into a go-github event to work with down the line
	event, err := flowevents.ParseEventWebHook(job.Event, *job.RawPayload)
	if err != nil {
		return errors.Wrap(err, "error parsing webhook")
	}

	// Also parse out as a webhookJSON struct, so we can look at fields not in the go-github event.
	// The struct may contain nil pointers and default values if the incoming payload is malformed.
	// This is checked by extractData in handleEvent.
	jsonEvent, err := unmarshalWebhook(*job.RawPayload)
	if err != nil {
		return errors.Wrap(err, "skipping malformed json payload")
	}

	shouldCheckRateLimit := (jsonEvent != nil &&
		jsonEvent.Repository != nil &&
		jsonEvent.Repository.ID != 0 &&
		p.ghtwirp.IsFeatureEnabledForRepository(ctx, ghclient.EnableWebhookRateLimitingDarkMode, jsonEvent.Repository.ID))
	if shouldCheckRateLimit && !p.webhookRateLimiter.Allow(ctx, jsonEvent.Repository.ID) {
		obs.Debug(ctx, "rejected by launch webhook processor rate limiter",
			kvp.Time("gh.launch.queued_at", job.EnqueuedAtTime()),
		)
		return tracing.RecordError(span, new(rate.QueueRateLimitError))
	}

	msg := queueRunMessage(ctx, obs, job.Event, jsonEvent)
	githubTenant, err := job.GitHubTenant(p.cfg.IsMultiTenant)
	if err != nil {
		p.sloReporter.ReportQueueRunError(ctx, obs, msg, "ExtractTenantIdFromJob")
		return errors.Wrap(err, "error getting github tenant id from job")
	}

	if err := githubTenant.Validate(p.cfg.IsMultiTenant); err != nil {
		p.sloReporter.ReportQueueRunError(ctx, obs, msg, "ExtractTenantIdFromJob")
		return errors.Wrap(err, "invalid github tenant")
	}

	// log proxima tenant information
	if p.cfg.IsMultiTenant {
		ctx = ctxstash.WithFields(ctx,
			kvp.String("gh.tenant.slug", githubTenant.Slug),
			kvp.Int64("gh.tenant.id", githubTenant.ID),
		)
	}

	// the github tenant id still needs to be set in the context so it can be used for scheduled workflow syncs
	// this will be removed once the sync code is refactored to explicitly require the github tenant id
	// See: https://github.com/github/actions-core-enterprise/issues/779
	ctx, err = ghtenant.ContextWithTenantID(ctx, githubTenant.ID, p.cfg.IsMultiTenant)
	if err != nil {
		p.sloReporter.ReportQueueRunError(ctx, obs, msg, "ExtractTenantIdFromJob")
		return errors.Wrap(err, "error setting github tenant id in current context")
	}

	ctx, err = ghtenant.ContextWithTenantSlug(ctx, githubTenant.Slug, p.cfg.IsMultiTenant)
	if err != nil {
		p.sloReporter.ReportQueueRunError(ctx, obs, msg, "ExtractTenantIdFromJob")
		return errors.Wrap(err, "error setting github tenant slug in current context")
	}

	ctx = p.ctxWithCustomerLabel(ctx, jsonEvent)

	errGroup := &panicmultierrgroup.Group{}

	if repoEvent, ok := event.(*github.RepositoryEvent); ok {
		repositoryCtx := callcounter.WithCounter(appcontext.CopyRequestMetadata(ctx), "webhooks.processor.handleRepository")

		errGroup.Go(func() error {
			err := p.handleRepository(repositoryCtx, obs, repoEvent)
			if err != nil {
				callcounter.EmitHistogram(repositoryCtx, obs, statter.Tags{"result": "error"})
				obs.Error(ctx, "error in handle repository", kvp.Err(err))
				return errors.Wrap(err, "handle repository error")
			}
			callcounter.EmitHistogram(repositoryCtx, obs, statter.Tags{"result": "success"})
			return nil
		})
	}

	if pushEvent, ok := event.(*github.PushEvent); ok {
		// Note, Sender == Actor for push events
		if pushEvent.Sender != nil && pushEvent.Sender.GetID() != 0 && pushEvent.Sender.GetNodeID() != "" {
			pushCtx := callcounter.WithCounter(appcontext.CopyRequestMetadata(ctx), "webhooks.processor.handlePush")
			errGroup.Go(func() error {
				p.handlePush(pushCtx, obs, pushEvent)
				callcounter.EmitHistogram(pushCtx, obs, statter.Tags{"result": "success"})
				return nil
			})
		}
	}

	// Spin off processing of a synthetic event if needed.
	if syntheticEvent, ok := getSyntheticEvent(job.Event); ok {
		syntheticCtx := callcounter.WithCounter(appcontext.CopyRequestMetadata(ctx), "webhooks.processor.handleEventSynthetic")
		syntheticJob := job
		errGroup.Go(func() error {
			syntheticJob.Event = syntheticEvent // Copied by value, so this should not change the original

			obs.Counter(syntheticCtx, "launch-worker.synthetic.event_type", statter.Tags{"synthetic_event": syntheticEvent}, 1)
			span.SetAttributes(attribute.String("gh.launch.event.name", syntheticEvent))

			syntheticCtx = ctxstash.WithFields(syntheticCtx, kvp.String("gh.launch.synthetic_event.name", syntheticEvent))
			obs.Debug(syntheticCtx, "passing synthetic event to worker")

			err := p.handleEvent(syntheticCtx, observability.CopyCheckpoints(obs), syntheticJob, event, jsonEvent, sanitizedPayload, isFinalAttempt, githubTenant)
			if err != nil {
				callcounter.EmitHistogram(syntheticCtx, obs, statter.Tags{"result": "error"})
				obs.Error(ctx, "error in handleEvent for synthetic event", kvp.Err(err))
				return errors.Wrap(err, "synthetic event error")
			}
			callcounter.EmitHistogram(syntheticCtx, obs, statter.Tags{"result": "success"})
			return nil
		})
	}

	errGroup.Go(func() error {
		err := p.handleEvent(ctx, obs, job, event, jsonEvent, sanitizedPayload, isFinalAttempt, githubTenant)
		if err != nil {
			obs.Error(ctx, "error in handleEvent for primary event", kvp.Err(err))
			return errors.Wrap(err, "primary event error")
		}
		return nil
	})

	if errs := errGroup.Wait(); errs.ErrorOrNil() != nil {
		callcounter.EmitHistogram(ctx, obs, statter.Tags{"result": "error", "event": job.Event})
		obs.Error(ctx, "webhook processor returning errors", kvp.Int("gh.launch.error.count", len(errs.Errors)))
		return errs
	}

	callcounter.EmitHistogram(ctx, obs, statter.Tags{"result": "success", "event": job.Event})

	return nil
}

func sanitizePayload(data []byte) ([]byte, error) {
	unsanitizedData := map[string]any{}
	if err := json.Unmarshal(data, &unsanitizedData); err != nil {
		return nil, err
	}
	sanitizedData := map[string]any{}
	for k, v := range unsanitizedData {
		switch k {
		case "meta", "installation", "actions_meta":
			continue

		default:
			sanitizedData[k] = v
		}
	}
	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(sanitizedData); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func (p *Processor) ctxWithCustomerLabel(ctx context.Context, jsonEvent *webhookJSON) context.Context {
	if jsonEvent.Repository == nil {
		return ctx
	}

	if jsonEvent.Repository.Owner == nil {
		return ctx
	}

	label := p.labeler.LabelFor(jsonEvent.Repository.Owner.Login, "")

	if label == "" {
		return ctx
	}

	return ctxstash.WithTags(ctx, stats.Tags{
		"customer_label": label,
	})
}

func queueRunMessage(ctx context.Context, obs *observability.Observability, eventName string, jsonEvent *webhookJSON) *hydro_schemas_github_actions_v0.QueueRun {
	var actorID, ownerID, repoID string

	if jsonEvent.Actor != nil {
		actorID = jsonEvent.Actor.NodeID
	}

	if jsonEvent.Repository != nil {
		if jsonEvent.Repository.Owner != nil {
			ownerID = jsonEvent.Repository.Owner.NodeID
		}
		repoID = jsonEvent.Repository.NodeID
	}

	return slometrics.NewQueueRunMessage(
		ctx,
		obs,
		slometrics.ActorID(actorID),
		slometrics.OwnerID(ownerID),
		slometrics.RepositoryID(repoID),
		eventName,
		jsonEvent.EventAction)
}

// Package hydro contains the dispatcher and event type mapping for handling Hydro events.
package hydro

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/events"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"google.golang.org/protobuf/proto"
)

type queue interface {
	QueueJob(ctx context.Context, job sweagentd.AqueductJob) (string, error)
}

type Dispatcher struct {
	obsv             observability.Exporters
	ffClient         featureflags.Client
	ghFactory        github.ClientFactoryInterface
	queue            queue
	eventHandler     events.EventsHandler
	ghTwirp          githubtwirp.ClientInterface
	environment      config.Environment
	environmentName  string
	appProvider      *agenticapp.Provider
	automationLookup automations.Lookup
}

func NewDispatcher(
	obsv observability.Exporters,
	ffClient featureflags.Client,
	ghFactory github.ClientFactoryInterface,
	queue queue,
	eventHandler events.EventsHandler,
	ghTwirp githubtwirp.ClientInterface,
	environment config.Environment,
	environmentName string,
	appProvider *agenticapp.Provider,
	automationLookup automations.Lookup,
) *Dispatcher {
	return &Dispatcher{
		obsv:             obsv,
		ffClient:         ffClient,
		ghFactory:        ghFactory,
		queue:            queue,
		eventHandler:     eventHandler,
		ghTwirp:          ghTwirp,
		environment:      environment,
		environmentName:  environmentName,
		appProvider:      appProvider,
		automationLookup: automationLookup,
	}
}

// canProcessTriggers reports whether this dispatcher instance is configured to
// evaluate automation triggers. The service dispatcher has a nil automationLookup
// (it only processes agent run completions), while the worker dispatcher has a
// non-nil automationLookup backed by the agent config store.
func (d *Dispatcher) canProcessTriggers() bool {
	return d.automationLookup != nil
}

func (d *Dispatcher) Dispatch(ctx context.Context, m hydro_lib.Message) error {
	// Let's start with a consolidated request ID for our background job
	if requestID := requestid.GetGitHubRequestID(ctx); requestID == "" {
		ctx = requestid.WithNewGitHubRequestID(ctx)
	}

	var err error

	var envelope hydro_pb.Envelope
	if err := proto.Unmarshal(m.Value, &envelope); err != nil {
		return fmt.Errorf("unmarshaling envelope: %w", err)
	}

	// Add the request context data to the context
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{
		HydroMessage: &requestctx.HydroEvent{
			EnvelopeID: envelope.Id,
			Topic:      m.Topic,
			Partition:  m.Partition,
			Offset:     m.Offset,
		},
	})

	if d.environment == config.EnvironmentProxima {
		id, slug, err := HydroTenantHeaders(m.Headers)
		if err != nil {
			return fmt.Errorf("getting hydro tenant headers: %w", err)
		}

		requestctx.AddTenantID(ctx, id)
		requestctx.AddTenantSlug(ctx, slug)
	}

	tags, _, kvps := requestctx.ToTelemetry(ctx, nil)
	logger := d.obsv.Logger.WithContext(ctx).WithFields(kvps...)

	logger.Info("start: hydro event")
	d.obsv.Statter.Counter("hydro.event_received", tags, 1)

	start := time.Now()
	processed, err := d.dispatch(ctx, logger, m.Topic, &envelope)
	duration := time.Since(start)

	// Reload the request context data to get the latest values,
	// for anything that was added in the dispatch method
	tags, ex, kvps := requestctx.ToTelemetry(ctx, nil)
	logger = d.obsv.Logger.WithContext(ctx).WithFields(kvps...)

	// NOTE: Given how queuing works, and err will **never** bubble up from the underlying event handler
	// to the dispatcher. Add error logic related to handlers to events.Handler.Process(...) instead.
	if err != nil {
		if errors.Is(err, context.Canceled) {
			// If the context is canceled, that means the consumer is shutting down
			// And the errors will not be sent to Splunk / Sentry / Datadog
			return err
		}

		// If the error is not a context.Canceled error, we want to report it
		// to Sentry and log it, because it is unusual to get here. Most errors
		// happen in the event handlers, and are bubbled up to the event queue.
		d.obsv.Statter.Counter("hydro.event_error", tags, 1)
		logger.WithError(err).Error("hydro event error")

		// Report the error to Sentry
		_ = d.obsv.Reporter.Report(ctx, err, ex)

		// It is important that we return errors from this method, as the hydro
		// consumer will retry the message if we do. This is important for
		// transient errors, such as network issues and to ensure we don't drop
		// messages.
		// return err

		// FOR NOW: we are encountering too many errors that we aren't handling properly.
		// We are going to log the error and return nil so that the message is acked and
		// we can move on. This will prevent infinite retries that cause rate-limiting.
		return nil
	}

	if processed {
		d.obsv.Statter.DistributionMs("hydro.dispatch_dist", tags, duration)
		logger.Info("done: hydro event", kvp.Duration("duration", duration))
	}

	return nil
}

// We need to consume the hydro events at least as fast as they are produced,
// otherwise we get behind and a lag builds up between when the event is produced
// and when we consume it.
// We also want to avoid unnecessary processing, token minting, and API calls for
// events that we don't care about.
//
// We do this by "short-circuiting" the event processing as soon as we have enough
// information to determine whether or not we should process or ignore the event.
func (d *Dispatcher) dispatch(ctx context.Context, logger log.Logger, topic string, envelope *hydro_pb.Envelope) (bool, error) {
	// ensure the topic is one we expect to handle
	if !slices.Contains(topics.All, topic) {
		logger.Error("unknown topic")
		return false, fmt.Errorf("unknown topic: %s", topic)
	}

	// before we do any event processing, check if the topic should be processed
	if !d.shouldProcessTopic(ctx, topic) {
		logger.Info("skipping event based on topic filter")
		d.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "topic_filter", "topic": topic}, 1)
		return false, nil
	}

	// unmarshal the message from the envelope and create the durable event
	// object that we'll use to handle the event.
	message, event, err := EventForTopic(ctx, topic, envelope, d.appProvider)
	if err != nil {
		if IsMessageNotApplicable(err) {
			logger.Info("event is not considered applicable, skipping processing")
			d.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "not_applicable", "topic": topic}, 1)
			return false, nil
		}
		return false, fmt.Errorf("failed to get event from hydro message: %w", err)
	}

	// EventForTopic has side effects, and loads data into our telemetry bag in the context.
	// In order to get those values into our logger, we need to reload the telemetry data.
	logger = d.obsv.LoggerWithTelemetry(ctx)

	// STAGING / PRODUCTION ROUTING OF EVENTS HAPPENS HERE
	// Move only with extreme caution. Any code changes above this point happen for
	// all events processed on both staging and production environments.
	if !d.shouldEnvironmentDispatchEvent(ctx, event) {
		logger.Info("skipping event based on environment filter")
		d.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "environment_filter", "topic": topic}, 1)
		return false, nil
	}

	// before making calls to twirp, vexi, etc., check the hydrated message and
	// event objects to determine if we should continue processing the event.

	if !d.shouldProcessMessage(ctx, message) {
		logger.Info("skipping event based on message filter")
		d.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "message_filter", "topic": topic}, 1)
		return false, nil
	}

	// Gate trigger events at the dispatcher boundary before any trigger store
	// lookups, enablement checks, admin policy checks, or queueing.
	// Skip on Service dispatchers so dual-listed events (e.g. PullRequestMerge for cancellation) aren't treated as triggers.
	trigger := ""
	if d.canProcessTriggers() {
		trigger = triggerForEvent(event)
	}
	isTriggerEvent := trigger != ""
	if isTriggerEvent && isPublicRepo(event) && featureflags.ShouldSkipPublicRepoAutomations(ctx, d.ffClient, event) {
		logger.Info("skipping trigger event for public repository")
		d.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "public_repository", "topic": topic}, 1)
		return false, nil
	}
	if isTriggerEvent && !d.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentTriggers, event) {
		logger.Info("skipping trigger event because custom agent triggers are disabled")
		d.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "trigger_feature_flag", "topic": topic}, 1)
		return false, nil
	}

	if !d.shouldProcessEvent(ctx, event) {
		logger.Info("skipping event based on event filter")
		d.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "event_filter", "topic": topic}, 1)
		return false, nil
	}

	// we may skip enablement checks for events used only to update internal state
	if d.shouldCheckActorEnablement(ctx, event) {
		enabled, cfg, err := d.checkEnablement(ctx, event)
		if err != nil {
			return false, fmt.Errorf("failed to assert repo enabled: %w", err)
		}
		if !enabled {
			logger.Info("skipping event because coding agent is not considered enabled for the event content")
			d.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "not_enabled", "topic": topic}, 1)
			return false, nil
		}

		// Admin automations policy gate; trigger is empty for non-trigger events/dispatchers so they pass through.
		if trigger != "" && d.automationLookup != nil &&
			d.automationLookup.AutomationsDisabledFromConfig(ctx, cfg, event.GetRepositoryID(), trigger) {
			d.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "automations_disabled", "topic": topic}, 1)
			return false, nil
		}
	}

	logger.Info("enqueuing event to aqueduct")

	eventJob := jobs.ToEventJob(ctx, topic, envelope, message, event, trigger)
	_, err = d.queue.QueueJob(ctx, eventJob)
	if err != nil {
		return false, fmt.Errorf("failed to queue event job: %w", err)
	}

	return true, nil
}

// checkEnablement checks if the repository is enabled for Copilot SWE Agent API.
// It ALSO sneakily adds tenant slug and tenant ID to the context if they are
// present in the repository configuration response for Proxima.
// The first time we interact with a repository is really the first time we are
// guaranteed to have the tenant slug and tenant ID available.
//
// Returns the cfg so callers can reuse it (e.g. for the admin policy gate)
// without a second IsAgentEnabled call. cfg is nil only when no Twirp call was
// made (e.g. user is on CopilotSWEAgentAPIDisallow).
func (d *Dispatcher) checkEnablement(ctx context.Context, event sweagentd.Event) (shouldConsiderEnabled bool, cfg *sweagentdtwirp.ConfigurationForRepositoryResponse, err error) {
	tags, _, kvps := requestctx.ToTelemetry(ctx, nil)

	actorID := event.GetActorID()
	repositoryID := event.GetRepositoryID()

	if d.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentAPIDisallow, actorID) {
		d.obsv.Statter.Counter("repo_enablement", tags.Merge(stats.Tags{"was_enabled": "false"}), 1)
		d.obsv.Logger.WithContext(ctx).WithFields(kvps...).Info("Ignoring Hydro event because user is flagged")
		return false, nil, nil
	}

	enabled, result, err := d.ghTwirp.IsAgentEnabled(ctx, event.GetAgentID(), actorID, repositoryID)
	if err != nil {
		return false, nil, fmt.Errorf("failed to get monolith configuration for repository: %w", err)
	}
	if result != nil && !d.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentTwirpProximaHookHeadersOnly) {
		if result.GetTenantSlug() != "" {
			err = requestctx.AddTenantSlug(ctx, result.GetTenantSlug())
			if err != nil {
				return false, nil, fmt.Errorf("adding tenant slug to context: %w", err)
			}
		}

		if result.GetTenantId() != "" {
			err = requestctx.AddTenantID(ctx, result.GetTenantId())
			if err != nil {
				return false, nil, fmt.Errorf("adding tenant id to context: %w", err)
			}
		}
	}

	d.obsv.Statter.Counter("repo_enablement", tags.Merge(stats.Tags{"was_enabled": strconv.FormatBool(enabled)}), 1)

	if !enabled {
		d.obsv.LoggerWithTelemetry(ctx).Info("Ignoring assignment because repo is not enabled for agent")
	}

	return enabled, result, nil
}

func HydroTenantHeaders(headers map[string]string) (string, string, error) {
	id := ""
	slug := ""

	if headers == nil {
		return id, slug, nil
	}

	found, ok := headers[requestctx.GitHubTenantIDHeader]
	if ok {
		id = found
	}

	found, ok = headers[requestctx.GitHubTenantHeader]
	if ok {
		slug = found
	}

	return id, slug, nil
}

// triggerForEvent returns the trigger name for routing the event job to the
// correct queue, or empty string for events that aren't trigger-based.
func triggerForEvent(event sweagentd.Event) string {
	switch e := event.(type) {
	case *events.WorkflowRunCompletedEvent:
		return e.TriggerName()
	case *events.IssueCreatedEvent:
		_ = e
		return "issue_created"
	case *events.AutomationRunRequestedEvent:
		_ = e
		return "automation_run_requested"
	case *events.PullRequestOpenedEvent:
		_ = e
		return "pull_request_opened"
	case *events.PullRequestStateChangedEvent:
		if e.PullRequest != nil && e.PullRequest.State == events.PullRequestStateMerged {
			return "pull_request_merged"
		}
		return ""
	case *events.PullRequestSynchronizeEvent:
		_ = e
		return "pull_request_synchronize"
	default:
		return ""
	}
}

// isPublicRepo returns true if the event carries enough information at the
// dispatcher level to determine that the repository is public. Currently only
// IssueCreatedEvent embeds repository visibility in its hydro payload.
// Other trigger event types (e.g. WorkflowRunCompletedEvent) return false here
// and rely on an API call in their handler to resolve visibility. If those
// events gain visibility information in their payloads in the future, add
// them to this function.
func isPublicRepo(event sweagentd.Event) bool {
	e, ok := event.(*events.IssueCreatedEvent)
	return ok && e.Repo != nil && e.Repo.IsPublic
}

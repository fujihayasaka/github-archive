// Package agenticappsync handles Hydro IntegrationUpdate and IntegrationCreate
// events to reload the agentic app provider registry when a relevant GitHub App
// is created or updated.
package agenticappsync

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"google.golang.org/protobuf/proto"
)

// Handler processes IntegrationUpdate and IntegrationCreate Hydro events and
// reloads the agentic app provider registry when a relevant integration is
// created or updated.
type Handler struct {
	obsv        observability.Exporters
	ghTwirp     githubtwirp.ClientInterface
	cfg         *config.Config
	appProvider *agenticapp.Provider
}

// NewHandler creates a new integration sync handler.
func NewHandler(
	obsv observability.Exporters,
	ghTwirp githubtwirp.ClientInterface,
	cfg *config.Config,
	appProvider *agenticapp.Provider,
) *Handler {
	return &Handler{
		obsv:        obsv,
		ghTwirp:     ghTwirp,
		cfg:         cfg,
		appProvider: appProvider,
	}
}

// Dispatch is the Hydro MessageHandler entry point. It processes raw Hydro
// messages containing IntegrationUpdate or IntegrationCreate events.
func (h *Handler) Dispatch(ctx context.Context, m hydro_lib.Message) error {
	if requestID := requestid.GetGitHubRequestID(ctx); requestID == "" {
		ctx = requestid.WithNewGitHubRequestID(ctx)
	}

	ctx = requestctx.AddData(ctx, &requestctx.CtxData{
		HydroMessage: &requestctx.HydroEvent{
			Topic:     m.Topic,
			Partition: m.Partition,
			Offset:    m.Offset,
		},
	})

	var envelope hydro_pb.Envelope
	err := proto.Unmarshal(m.Value, &envelope)
	if err != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("agenticappsync: failed to unmarshal envelope")
		h.obsv.Increment(ctx, "integrationsync.envelope_error", nil)
		return nil // ack to prevent infinite retries
	}

	requestctx.Data(ctx).HydroMessage.EnvelopeID = envelope.Id
	logger := h.obsv.LoggerWithTelemetry(ctx)

	var handler func(context.Context, *hydro_pb.Envelope) error
	switch m.Topic {
	case topics.IntegrationUpdate:
		handler = h.handleIntegrationUpdate
	case topics.IntegrationCreate:
		handler = h.handleIntegrationCreate
	default:
		logger.Error("agenticappsync: unexpected topic", kvp.String("topic", m.Topic))
		return nil
	}

	logger.Info("start: integrationsync hydro event")
	h.obsv.Increment(ctx, "integrationsync.event_received", nil)

	start := time.Now()
	err = handler(ctx, &envelope)
	duration := time.Since(start)

	logger = h.obsv.LoggerWithTelemetry(ctx)

	if err != nil {
		h.obsv.Increment(ctx, "integrationsync.event_error", nil)
		logger.WithError(err).Error("agenticappsync: dispatch error")
		return nil // ack to prevent infinite retries
	}

	h.obsv.DistributionMs(ctx, "integrationsync.dispatch_dist", nil, duration)
	logger.Info("done: integrationsync hydro event", kvp.Duration("duration", duration))

	return nil
}

func (h *Handler) handleIntegrationUpdate(ctx context.Context, envelope *hydro_pb.Envelope) error {
	msg := new(githubv1.IntegrationUpdate)
	err := proto.Unmarshal(envelope.GetMessage(), msg)
	if err != nil {
		return goerrors.Errorf("parsing IntegrationUpdate: %w", err)
	}

	return h.reloadIfManaged(ctx, msg.GetIntegration())
}

func (h *Handler) handleIntegrationCreate(ctx context.Context, envelope *hydro_pb.Envelope) error {
	msg := new(githubv1.IntegrationCreate)
	err := proto.Unmarshal(envelope.GetMessage(), msg)
	if err != nil {
		return goerrors.Errorf("parsing IntegrationCreate: %w", err)
	}

	return h.reloadIfManaged(ctx, msg.GetIntegration())
}

func (h *Handler) reloadIfManaged(ctx context.Context, integration *entities.Integration) error {
	if integration == nil {
		h.obsv.Increment(ctx, "integrationsync.event_skipped", stats.Tags{"reason": "nil_integration"})
		return nil
	}

	integrationID := int64(integration.GetId())
	logger := h.obsv.LoggerWithTelemetry(ctx)

	// Only process events for integrations that have an agent source
	if integration.GetAgentSource() == nil || integration.GetAgentSource().GetUrl() == "" {
		h.obsv.Increment(ctx, "integrationsync.event_skipped", stats.Tags{"reason": "unrelated_integration"})
		return nil
	}

	logger.Info("agenticappsync: reloading agentic apps",
		kvp.Int64("integration_id", integrationID),
		kvp.String("integration_name", integration.GetName()),
	)

	copilotApp, apps, err := agenticapp.AgenticApps(ctx, h.cfg, h.ghTwirp, h.obsv)
	if err != nil {
		h.obsv.Increment(ctx, "integrationsync.reload_error", nil)
		return goerrors.Errorf("reloading agentic apps: %w", err)
	}

	h.appProvider.Reload(copilotApp, apps...)

	// Log information about the newly loaded apps for observability
	logger.Info("agenticappsync: copilot app loaded",
		kvp.Int64("app_id", copilotApp.AppID()),
		kvp.String("app_name", copilotApp.AppName()),
		kvp.String("bot_login", copilotApp.BotLogin()),
		kvp.String("mentionable_slug", copilotApp.MentionableSlug()),
	)

	for _, app := range apps {
		logger.Info("agenticappsync: agentic app loaded",
			kvp.Int64("app_id", app.AppID()),
			kvp.String("app_name", app.AppName()),
			kvp.String("bot_login", app.BotLogin()),
			kvp.String("mentionable_slug", app.MentionableSlug()),
			kvp.String("compute_slug", app.ComputeSlug()),
			kvp.Bool("is_global", app.IsGlobalApp()),
			kvp.Bool("is_partner", app.IsPartnerApp()),
			kvp.Bool("is_third_party", app.IsThirdPartyApp()),
		)
	}

	h.obsv.Increment(ctx, "integrationsync.reload_success", nil)

	logger.Info("agenticappsync: agentic apps reloaded successfully",
		kvp.Int("app_count", len(apps)+1),
	)

	return nil
}

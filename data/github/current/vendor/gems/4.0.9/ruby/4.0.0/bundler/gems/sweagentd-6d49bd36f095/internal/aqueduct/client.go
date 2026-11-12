// Package aqueduct provides a client for interacting with the Aqueduct job queueing service.
package aqueduct

import (
	"context"
	"net/http"
	"strconv"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"go.opentelemetry.io/otel/codes"
)

// Client wraps the Aqueduct client with application-specific configuration.
type Client struct {
	appName                       string
	aqueductURL                   string
	apiKey                        string
	apiKeyVersion                 int
	client                        aqueduct.Client
	obsv                          observability.Exporters
	statsConfig                   *aqueduct.StatsConfig
	defaultRedeliveryDelaySeconds int
	queueDepthCache               cache.Store
	queueDepthCacheTTL            time.Duration
}

// NewClient creates a new Aqueduct client with the provided configuration.
func NewClient(ctx context.Context, obsv observability.Exporters, appName string, options ...ClientOption) (*Client, error) {
	ctx, span := obsv.Tracer.Start(ctx, "aqueduct.NewClient")
	defer span.End() // Ensure the span is ended

	methodLogger := obsv.Logger.WithContext(ctx).WithFields(
		kvp.String("code.function", "NewClient"),
		kvp.String("code.namespace", "aqueduct"),
	)
	defer obsv.LogWithDuration(ctx, methodLogger, time.Now(), "NewClient")

	ac := &Client{
		appName:                       appName,
		aqueductURL:                   "",
		apiKey:                        "",
		apiKeyVersion:                 0,
		obsv:                          obsv,
		defaultRedeliveryDelaySeconds: defaultRedeliveryDelaySeconds,
	}
	for _, option := range options {
		option(ac)
	}

	methodLogger.Info("Initializing Aqueduct client")

	err := ac.configureClient()
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		methodLogger.WithError(err).Error("error creating Aqueduct client")
		return nil, err
	}

	methodLogger.Info("Aqueduct client created successfully")

	return ac, nil
}

// NewClientFromConfig creates a new Aqueduct client, configured according to the environment.
func NewClientFromConfig(ctx context.Context, cfg *config.Config, obsv observability.Exporters) (*Client, error) {
	aqueductOpts := []ClientOption{
		WithAqueductURL(cfg.AqueductURL),
		WithDefaultRedeliveryDelay(cfg.AqueductRequeueIntervalSeconds),
	}
	aqueductAppName := "sweagentd"
	if cfg.Environment == config.EnvironmentStaging {
		switch cfg.EnvironmentName {
		case "staging":
			aqueductAppName = "sweagentd-staging"
			aqueductOpts = append(aqueductOpts, WithAPIKey(cfg.AqueductStagingAPIKey), WithAPIKeyVersion(cfg.AqueductStagingAPIKeyVersion))
		case "staging-jedi-knight":
			aqueductAppName = "sweagentd-staging-jedi-knight"
			aqueductOpts = append(aqueductOpts, WithAPIKey(cfg.AqueductStagingJediKnightAPIKey), WithAPIKeyVersion(cfg.AqueductStagingJediKnightAPIKeyVersion))
		case "staging-sith-lord":
			aqueductAppName = "sweagentd-staging-sith-lord"
			aqueductOpts = append(aqueductOpts, WithAPIKey(cfg.AqueductStagingSithLordAPIKey), WithAPIKeyVersion(cfg.AqueductStagingSithLordAPIKeyVersion))
		case "staging-baby-yoda":
			aqueductAppName = "sweagentd-staging-baby-yoda"
			aqueductOpts = append(aqueductOpts, WithAPIKey(cfg.AqueductStagingBabyYodaAPIKey), WithAPIKeyVersion(cfg.AqueductStagingBabyYodaAPIKeyVersion))
		default:
			return nil, goerrors.Errorf("invalid environment name for staging: %s", cfg.EnvironmentName)
		}
	} else {
		aqueductOpts = append(aqueductOpts, WithAPIKey(cfg.AqueductAPIKey), WithAPIKeyVersion(cfg.AqueductAPIKeyVersion))
	}

	// Create the aqueduct client
	return NewClient(ctx, obsv, aqueductAppName, aqueductOpts...)
}

// AppName returns the application name.
func (ac *Client) AppName() string { return ac.appName }

// AqueductURL returns the Aqueduct service URL.
func (ac *Client) AqueductURL() string { return ac.aqueductURL }

// InternalClient returns the underlying Aqueduct client.
func (ac *Client) InternalClient() aqueduct.Client { return ac.client }

// QueueDepth returns the current depth (number of pending jobs) for the named
// queue under this client's app. Used by scheduling hooks to throttle dequeue
// rate or widen jitter under load. Mirrors Launch's pattern (`launch/internal/
// schedules/worker.go`'s `getQueueDepth`).
//
// When the client has been configured with `WithQueueDepthCache`, results are
// cached per queue name for the configured TTL. This matches Launch's 60s
// cached read and keeps Twirp pressure on Aqueduct bounded even when called
// from a hot tick loop.
func (ac *Client) QueueDepth(ctx context.Context, queue string) (int64, error) {
	if ac.queueDepthCache != nil && ac.queueDepthCacheTTL > 0 {
		key := queueDepthCacheKey(ac.appName, queue)
		if cached, ok := ac.queueDepthCache.Get(key); ok {
			depth, parseErr := strconv.ParseInt(cached, 10, 64)
			if parseErr == nil {
				return depth, nil
			}
		}
		depth, err := ac.client.QueueDepth(ctx, ac.appName, queue)
		if err != nil {
			return 0, err
		}
		ac.queueDepthCache.Set(key, strconv.FormatInt(depth, 10), ac.queueDepthCacheTTL)
		return depth, nil
	}
	return ac.client.QueueDepth(ctx, ac.appName, queue)
}

// queueDepthCacheKey namespaces queue-depth entries so they don't collide with
// other consumers of the shared cache store.
func queueDepthCacheKey(app, queue string) string {
	return "aqueduct.queue_depth/v1/" + app + "/" + queue
}

func (ac *Client) getAPIKey() string { return ac.apiKey }

func (ac *Client) getAPIKeyVersion() int { return ac.apiKeyVersion }

func (ac *Client) configureClient() error {
	if ac.client != nil {
		return goerrors.New("aqueduct client already exists")
	}

	// we need to create a new client
	// first, we need to check if the aqueduct URL is set
	if ac.aqueductURL == "" {
		return goerrors.New("aqueduct URL is not set")
	}
	statsConfig, err := aqueduct.NewStatsConfig(
		aqueduct.WithStatsClient(ac.obsv.Statter),
	)
	if err != nil {
		return goerrors.New("could not create stats config for aqueduct client")
	}
	ac.statsConfig = statsConfig

	opts := []aqueduct.ClientOption{
		aqueduct.WithIdempotentSend(true),
		aqueduct.WithClientStats(statsConfig),
		aqueduct.WithHTTPClient(&http.Client{
			Transport: observability.NewTelemetryRoundTripper(http.DefaultTransport, ac.obsv, "aqueduct", nil),
		}),
	}
	// if we have an API key and version, we'll use that.
	if ac.apiKey != "" {
		opts = append(
			opts,
			aqueduct.WithAPIKey(ac.apiKey),
			aqueduct.WithAPIKeyVersion(ac.apiKeyVersion),
		)
	}
	client, err := aqueduct.NewClient(
		ac.aqueductURL,
		opts...,
	)
	if err != nil {
		return goerrors.Errorf("failed to create Aqueduct client: %w", err)
	}
	ac.client = client
	return nil
}

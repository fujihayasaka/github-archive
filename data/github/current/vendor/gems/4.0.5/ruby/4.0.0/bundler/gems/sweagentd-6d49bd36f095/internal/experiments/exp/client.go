// Package exp provides local experiment evaluation using the exp-go-sdk
// wrapped by githubexp for GitHub-standard logging and metrics.
package exp

import (
	"context"
	"net/url"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	gosdk "github.com/github/exp-go-sdk/exp"
	"github.com/github/feature-management-client-go/githubexp"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/azureauth"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// ExperimentationClient defines the interface for experiment assignment.
type ExperimentationClient interface {
	ResilientStart(ctx context.Context, opts ...githubexp.ResilientStartOption) error
	GetAssignment(ctx context.Context, userParams map[string]string, requiredVariants, blockedVariants []string) *githubexp.AssignmentResult
}

// Assignment is an alias for *githubexp.AssignmentResult.
type Assignment = *githubexp.AssignmentResult

// ResilientStartOption is an alias for githubexp.ResilientStartOption.
type ResilientStartOption = githubexp.ResilientStartOption

// Re-export githubexp options.
var (
	WithPollInterval = githubexp.WithPollInterval
	WithMaxBackoff   = githubexp.WithMaxBackoff
	WithBlockingWait = githubexp.WithBlockingWait
)

var _ ExperimentationClient = (*Client)(nil)

// Client wraps githubexp.Client. If inner is nil, it behaves as a noop client that returns defaults.
type Client struct {
	inner   *githubexp.Client
	scopes  []string     // ExP subscription scopes to limit evaluated experiments
	statter stats.Client // for assignment request metrics
}

// ClientOption configures NewClient.
type ClientOption func(*clientOptions)

type clientOptions struct {
	source      gosdk.ConfigSource
	statsClient stats.Client
	tracer      githubexp.Tracer
	scopes      []string
}

// WithSource overrides the Azure Blob config source.
// Use gosdk.NewInMemorySource for mocking in tests:
//
//	client, _ := exp.NewClient(cfg, logger, exp.WithSource(
//	    gosdk.NewInMemorySource(map[string]string{"/my_flag": "treatment"}),
//	))
func WithSource(source gosdk.ConfigSource) ClientOption {
	return func(o *clientOptions) { o.source = source }
}

// WithStatsClient sets a go-stats client for metrics.
func WithStatsClient(client stats.Client) ClientOption {
	return func(o *clientOptions) { o.statsClient = client }
}

// WithTracer sets an OpenTelemetry tracer.
func WithTracer(tracer githubexp.Tracer) ClientOption {
	return func(o *clientOptions) { o.tracer = tracer }
}

// WithScopes sets ExP subscription scopes to limit which experiments are evaluated.
// This reduces assignment latency by avoiding evaluation of unrelated experiments.
func WithScopes(scopes []string) ClientOption {
	return func(o *clientOptions) { o.scopes = scopes }
}

// ClientConfig holds configuration for NewClient.
type ClientConfig struct {
	BlobURI       string // Azure Blob URI for experiment config
	AppName       string // Service name for metrics (default: "copilot-coding-agent")
	Enabled       bool   // When false, returns noop client
	IsDevelopment bool   // true: Azure CLI creds, false: Client Secret creds
	// TenantID is the Azure AD tenant ID for service principal authentication.
	// Required in production to access the ExP config blob in Azure Storage.
	// Derived from EXPERIMENTATION_SPN_NAME_tenant_id env var.
	TenantID string

	// ClientID is the Azure AD application (service principal) client ID.
	// Required in production to access the ExP config blob in Azure Storage.
	// Derived from EXPERIMENTATION_SPN_NAME_client_id env var.
	ClientID string
}

// NewClient creates a new experiment client.
func NewClient(cfg ClientConfig, logger log.Logger, opts ...ClientOption) (*Client, error) {
	var o clientOptions
	for _, opt := range opts {
		opt(&o)
	}

	appName := cfg.AppName
	if appName == "" {
		appName = "copilot-coding-agent"
	}

	if !cfg.Enabled {
		logger.Info("Azure ExP is disabled, returning no-op client")
		return &Client{inner: nil}, nil
	}

	source := o.source
	if source == nil {
		if cfg.BlobURI == "" {
			return nil, goerrors.New("BlobURI is required when ExP is enabled")
		}

		cred, err := newCredential(cfg)
		if err != nil {
			return nil, goerrors.Errorf("creating Azure credential for ExP: %w", err)
		}

		blobSource, err := gosdk.NewAzureBlobSource(cfg.BlobURI, cred)
		if err != nil {
			return nil, goerrors.Errorf("creating Azure Blob source for ExP: %w", err)
		}
		source = blobSource
	}

	// Build githubexp options
	var ghexpOpts []githubexp.ClientOption
	ghexpOpts = append(ghexpOpts, githubexp.WithLogger(logger))
	if o.statsClient != nil {
		ghexpOpts = append(ghexpOpts, githubexp.WithStatsClient(o.statsClient))
	}
	if o.tracer != nil {
		ghexpOpts = append(ghexpOpts, githubexp.WithTracer(o.tracer))
	}

	inner, err := githubexp.NewClient(source, appName, ghexpOpts...)
	if err != nil {
		return nil, goerrors.Errorf("creating githubexp client: %w", err)
	}

	return &Client{inner: inner, scopes: o.scopes, statter: o.statsClient}, nil
}

// NewNoopClient creates a disabled client that returns defaults.
func NewNoopClient() *Client {
	return &Client{inner: nil, scopes: nil, statter: nil}
}

// ResilientStart loads config and starts background polling. No-op if disabled.
func (c *Client) ResilientStart(ctx context.Context, opts ...githubexp.ResilientStartOption) error {
	if c.inner == nil {
		return nil
	}
	return c.inner.ResilientStart(ctx, opts...)
}

// GetAssignment returns variant assignment for the given user parameters.
// Scopes configured at client creation are automatically applied.
func (c *Client) GetAssignment(ctx context.Context, userParams map[string]string, requiredVariants, blockedVariants []string) *githubexp.AssignmentResult {
	if c.inner == nil {
		return githubexp.NewAssignmentResult(nil, "", 0)
	}
	if len(userParams) == 0 {
		if c.statter != nil {
			c.statter.Increment("exp.assignment.request", stats.Tags{"result": "no_params"})
		}
		return githubexp.NewAssignmentResult(nil, "", 0)
	}
	return c.inner.GetAssignment(ctx, userParams, c.scopes, requiredVariants, blockedVariants)
}

// NewAssignmentResult creates an AssignmentResult for testing.
func NewAssignmentResult(featureVariables map[string]string, assignmentContext string, dataVersion uint64) *githubexp.AssignmentResult {
	return githubexp.NewAssignmentResult(featureVariables, assignmentContext, dataVersion)
}

func newCredential(cfg ClientConfig) (azcore.TokenCredential, error) {
	if cfg.IsDevelopment {
		cred, err := azidentity.NewAzureCLICredential(nil)
		if err != nil {
			return nil, goerrors.Errorf("creating Azure CLI credential: %w", err)
		}
		return cred, nil
	}

	return azureauth.NewAzureCredential(cfg.TenantID, cfg.ClientID)
}

// redactBlobURI returns only the host and path of a blob URI, stripping
// query parameters that may contain SAS tokens or other credentials.
func redactBlobURI(blobURI string) string {
	u, err := url.Parse(blobURI)
	if err != nil {
		return "[invalid-uri]"
	}
	return u.Host + u.Path
}

// NewClientFromConfig creates a new ExperimentationClient from sweagentd config.
// Returns a noop client for Proxima or when ExperimentationSDKBlobURI is not set.
func NewClientFromConfig(ctx context.Context, cfg *config.Config, obsv observability.Exporters) (ExperimentationClient, error) {
	logger := obsv.Logger
	statter := obsv.Statter

	if cfg.Environment == config.EnvironmentProxima {
		logger.Info("Proxima environment: returning noop exp client")
		return NewNoopClient(), nil
	}

	if cfg.ExperimentationSDKBlobURI == "" {
		logger.Info("exp SDK disabled: ExperimentationSDKBlobURI not configured")
		return NewNoopClient(), nil
	}

	logger.Info("creating exp SDK client",
		kvp.String("blob_uri_host", redactBlobURI(cfg.ExperimentationSDKBlobURI)))

	isDev := cfg.Environment == config.EnvironmentDevelopment

	// Parse comma-separated scopes
	var scopes []string
	if cfg.ExperimentationSDKScopes != "" {
		for s := range strings.SplitSeq(cfg.ExperimentationSDKScopes, ",") {
			s = strings.TrimSpace(s)
			if s != "" {
				scopes = append(scopes, s)
			}
		}
	}

	logger.Info("exp SDK scopes configured", kvp.Int("scope_count", len(scopes)))

	client, err := NewClient(ClientConfig{
		Enabled:       true,
		BlobURI:       cfg.ExperimentationSDKBlobURI,
		IsDevelopment: isDev,
		TenantID:      cfg.ExperimentationSPNTenantID,
		ClientID:      cfg.ExperimentationSPNClientID,
	}, logger,
		WithStatsClient(statter),
		WithTracer(obsv.Tracer),
		WithScopes(scopes),
	)
	if err != nil {
		logger.Error("failed to create exp SDK client, falling back to noop", kvp.Err(err))
		statter.Increment("exp.init.failure", stats.Tags{"reason": "client_creation"})
		_ = obsv.Reporter.Report(ctx, goerrors.Errorf("failed to create exp SDK client: %w", err), map[string]string{"class": "exp_init"})
		return NewNoopClient(), nil
	}

	// Start background polling (defaults: 5min poll, 5sec blocking wait, 5min max backoff)
	// See https://github.com/github/feature-management-client-go/blob/08bcc947da896bf3dccbc4f31c5cd9255062be86/githubexp/docs/api-reference.md#resilientstart
	err = client.ResilientStart(ctx)
	if err != nil {
		logger.Warn("exp SDK resilient start failed, will retry in background", kvp.Err(err))
		statter.Increment("exp.init.failure", stats.Tags{"reason": "resilient_start"})
	}

	return client, nil
}

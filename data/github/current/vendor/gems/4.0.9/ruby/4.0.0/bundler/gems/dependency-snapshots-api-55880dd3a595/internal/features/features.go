package features

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

// Client is an interface for Twirp Features API client.
type Client interface {
	IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error)
	IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error)
	IsFeatureFlagEnabledForUser(ctx context.Context, feature string, userID uint64) (bool, error)
	IsFeatureFlagEnabledForOrganization(ctx context.Context, feature string, organizationID uint64) (bool, error)
}

// NewFeaturesClient creates a new features Client that uses Vexi as primary and Twirp as fallback.
func NewFeaturesClient(ctx context.Context, cfg *config.Config, logger log.Logger, statter stats.Client) (Client, error) {
	var client Client
	twirpClient, err := NewTwirpFeaturesClient(statter, cfg.MonolithTwirpURL, cfg.MonolithTwirpHMACKey, cfg.DevStandaloneMode)
	if err != nil {
		return nil, err
	}
	vexiClient, err := NewVexiFeaturesClient(ctx, logger, statter, cfg.VexiHydroBrokers, cfg.DevStandaloneMode)
	if err != nil {
		client = twirpClient // fallback to twirp client if vexi client fails
		logger.Error("failed to initialize Vexi features client, falling back to Twirp client", kvp.String("exception.message", err.Error()))
	} else {
		client, err = WrapFeaturesClientWithFallback(vexiClient, twirpClient)
		if err != nil {
			return nil, errors.Wrap(err, "failed to create wrapped features client")
		}
	}
	// If any feature flags have been set via an envvar, then we wrap the client with an override layer.
	// This is primary used in integration testing to enable a limited set of flags for testing
	if overrides := enabledFlagOverrides(); len(overrides) > 0 {
		client = &flagOverrideClient{inner: client, overrides: overrides}
	}
	return client, nil
}

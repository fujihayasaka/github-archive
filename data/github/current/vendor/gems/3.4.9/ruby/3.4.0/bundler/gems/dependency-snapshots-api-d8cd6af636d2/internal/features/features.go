package features

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/github-telemetry-go/kvp"
	stats "github.com/github/go-stats"
	twirpauth "github.com/github/go-twirp/v2/client/auth"
	featuresapi "github.com/github/monolith-twirp-features/core/v1"
	"github.com/pkg/errors"
)

// Client is an interface for Twirp Features API client.
type Client interface {
	IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error)
	IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error)
}

// twirpFeaturesClient is an HTTP twirpFeaturesClient that manages feature flags via Twirp Features API.
// See more: https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/twirp/go/
type twirpFeaturesClient struct {
	client        featuresapi.FeaturesAPI
	devStandalone bool
	statter       stats.Client
}

// NewTwirpFeaturesClient creates and configures a client based on Twirp API URL and HMAC key.
func NewTwirpFeaturesClient(statter stats.Client, twirpAPIURL, hmacKey string, devStandalone bool) (Client, error) {
	twirpClient, err := twirpauth.NewRequestHMACSigner(hmacKey, http.DefaultClient)
	if err != nil {
		return nil, err
	}

	return &twirpFeaturesClient{
		client:        featuresapi.NewFeaturesAPIProtobufClient(twirpAPIURL, twirpClient),
		devStandalone: devStandalone,
		statter:       statter,
	}, nil
}

// IsFeatureFlagEnabled checks whether a given feature is enabled for any number of actors. For a global
// feature or a single actor, it still returns an array of bool so please use the first value of the result.
// feature (String) – the name of the feature.
// actors (Array<String>) – an array of actor IDs, formatted as "type:id". Example: ["User:1234", "Repository:2345"].
func (c *twirpFeaturesClient) IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error) {
	if c.devStandalone {
		// Dev standalone assumes all features are on. This could be trivially extended to have a default set of values.
		standaloneResults := make([]bool, len(actors))
		for i := range standaloneResults {
			standaloneResults[i] = true
		}
		return standaloneResults, nil
	}

	if len(actors) == 0 {
		if result, err := c.globalFeatureEnabled(ctx, feature); err != nil {
			return nil, err
		} else {
			return []bool{result}, nil
		}
	}

	return c.actorsFeatureEnabled(ctx, feature, actors)
}

// IsFeatureFlagEnabledForRepository checks whether a given feature is enabled for a repository.
// feature (String) – the name of the feature.
// repositoryID (uint64) – repository id to check
// Times out after one second.
func (c *twirpFeaturesClient) IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error) {
	isEnabled, err := c.IsFeatureFlagEnabled(ctx, feature, fmt.Sprintf("Repository:%v", repositoryID))
	if err != nil {
		return false, errors.Wrap(err, "the feature client errored while checking enablement")
	}

	return isEnabled[0], nil
}

// globalFeatureEnabled uses Twirp Features API to check if a given feature is enabled globally.
// times out after one second.
func (c *twirpFeaturesClient) globalFeatureEnabled(ctx context.Context, feature string) (bool, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "FeatureFlagTracing", "GlobalFeatureEnabled")
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer func() {
		ender()
		cancel()
	}()
	req := featuresapi.CheckGlobalFeatureRequest{Feature: feature}
	resp, err := c.client.CheckGlobalFeature(ctx, &req)
	if err != nil {
		if err == context.DeadlineExceeded && c.statter != nil {
			c.statter.Counter("features.timeout", stats.Tags{}, 1)
		}
		return false, errors.Wrap(err, "operation failed trying to call Twirp Features API")
	}

	contextlogger.Debug(ctx, "feature", kvp.String("feature_flag.key", feature), kvp.Bool("feature_flag.enabled", resp.IsEnabled))
	return resp.IsEnabled, nil
}

// actorsFeatureEnabled uses Twirp Features API to check if a given feature is enabled for an array of actors.
// times out after one second.
func (c *twirpFeaturesClient) actorsFeatureEnabled(ctx context.Context, feature string, actorIds []string) ([]bool, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "FeatureFlagTracing", "ActorFeatureEnabled")
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer func() {
		ender()
		cancel()
	}()

	req := featuresapi.CheckActorsFeatureRequest{Feature: feature, ActorIds: actorIds}
	resp, err := c.client.CheckActorsFeature(ctx, &req)

	if err != nil {
		if err == context.DeadlineExceeded && c.statter != nil {
			c.statter.Counter("features.timeout", stats.Tags{}, 1)
		}
		return nil, errors.Wrap(err, "operation failed trying to call Twirp Features API")
	}

	results := make([]bool, 0, len(actorIds))
	for _, r := range resp.Results {
		contextlogger.Debug(
			ctx,
			fmt.Sprintf(
				"feature name=%v actor=%v enabled=%v",
				feature,
				r.ActorId,
				strconv.FormatBool(r.IsEnabled),
			),
		)

		results = append(results, r.IsEnabled)
	}
	return results, nil
}

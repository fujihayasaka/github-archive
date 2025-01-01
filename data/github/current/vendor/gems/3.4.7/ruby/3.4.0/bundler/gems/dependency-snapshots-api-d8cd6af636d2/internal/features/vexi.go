package features

import (
	"context"
	"fmt"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"

	vx "github.com/github/feature-management-client-go/vexi/extensions"
	vexi "github.com/github/feature-management-client-go/vexi/v2"
	hydro_adapter "github.com/github/feature-management-client-go/vexi/v2/adapter/hydro"
	stats "github.com/github/go-stats"
)

var _ Client = (*vexiFeaturesClient)(nil)
var _ Client = (*clientWithFallback)(nil)

func newVexiHydroAdapter(ctx context.Context, logger log.Logger, statter stats.Client, brokers string) (*hydro_adapter.Adapter, error) {
	hydroAdapter, err := hydro_adapter.NewAdapterWithOwningServices(ctx,
		"dependency-snapshots-api", // App name will be used to broadcast metrics and uniquely identify telemetry from the service.
		// Vexi will only be able to access features that are scoped to one of the following services,
		// but don't go adding new ones casually! Each one brings a significant
		// performance cost, even if the service only owns a few flags.
		[]string{"dependency-snapshots-api", "github/dependency_graph"},
		hydro_adapter.WithLogger(logger),
		hydro_adapter.WithStatsClient(statter),
		hydro_adapter.WithHydroBrokers(brokers),
		hydro_adapter.WithSystemRootCA(),
		hydro_adapter.WithCuratedSegments(), // Optional, if you intend to evaluate staffshipped feature flags
	)
	return hydroAdapter, err
}

func newVexiClient(ctx context.Context, logger log.Logger, statter stats.Client, brokers string) (*vexi.Client, error) {
	hydro, err := newVexiHydroAdapter(ctx, logger, statter, brokers)
	if err != nil {
		return nil, err
	}

	if err := hydro.ResilientStart(ctx,
		hydro_adapter.WithMaxBlockingWait(500*time.Millisecond), // Maximum time to block on startup before returning an error.
		hydro_adapter.WithMaxBackoffWindow(5*time.Second),       // Maximum backoff window for retries.
	); err != nil {
		return nil, err
	}
	vexiClient, err := vexi.NewVexiClient(ctx,
		hydro,
		"dependency-snapshots-api", // The name of the application using the Vexi client.
		vexi.WithLogger(logger),
		vexi.WithStatsClient(statter),
	)
	if err != nil {
		return nil, err
	}

	logger.Info("Vexi client initialized",
		kvp.String("brokers", brokers),
		kvp.String("hydro_adapter", hydro.Name()),
	)
	return vexiClient, nil
}

type vexiFeaturesClient struct {
	client        *vexi.Client
	devStandalone bool
	statter       stats.Client
	logger        log.Logger
}

func NewVexiFeaturesClient(ctx context.Context, logger log.Logger, statter stats.Client, brokers string, devStandalone bool) (Client, error) {
	if len(brokers) == 0 {
		return nil, errors.New("No Vexi brokers provided, cannot create Vexi client")
	}
	vexiClient, err := newVexiClient(ctx, logger, statter, brokers)
	if err != nil {
		return nil, err
	}

	return &vexiFeaturesClient{
		client:        vexiClient,
		devStandalone: devStandalone,
		statter:       statter,
		logger:        logger,
	}, nil
}

func (c *vexiFeaturesClient) IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error) {
	if c.devStandalone {
		// Dev standalone assumes all features are on. This could be trivially extended to have a default set of values.
		standaloneResults := make([]bool, len(actors))
		for i := range standaloneResults {
			standaloneResults[i] = true
		}
		return standaloneResults, nil
	}

	vexiActors := make([]vexi.Actor, len(actors))
	for i, actor := range actors {
		vexiActors[i] = vexi.NewActor(actor)
	}

	results := make([]bool, len(vexiActors))
	for i, vexiActor := range vexiActors {
		isEnabled, err := c.client.IsEnabledWithError(ctx, feature, vexiActor)
		if err != nil {
			return nil, errors.Wrapf(err, "failed to check feature %q for actor %q", feature, vexiActor.VexiID())
		}
		results[i] = isEnabled
	}

	return results, nil
}

func (c *vexiFeaturesClient) IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error) {
	actor := vx.NewRepository(fmt.Sprintf("%v", repositoryID))
	isEnabled, err := c.IsFeatureFlagEnabled(ctx, feature, actor.VexiID())
	if err != nil {
		return false, errors.Wrap(err, "the feature client errored while checking enablement")
	}
	// Temporary logging to demonstrate that vexi is working. Remove once deployed and verified.
	contextlogger.Info(ctx, "Checked feature flag for repository",
		kvp.String("feature_flag.key", feature),
		kvp.String("feature_flag.client", "vexi"),
		kvp.Uint64("gh.repo.id", repositoryID),
		kvp.Bool("feature_flag.enabled", isEnabled[0]),
	)

	return isEnabled[0], nil
}

type clientWithFallback struct {
	client   Client
	fallback Client
}

func WrapFeaturesClientWithFallback(primary, fallback Client) (Client, error) {
	return &clientWithFallback{
		client:   primary,
		fallback: fallback,
	}, nil
}

func (c *clientWithFallback) IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error) {
	results, err := c.client.IsFeatureFlagEnabled(ctx, feature, actors...)
	if err != nil {
		return c.fallback.IsFeatureFlagEnabled(ctx, feature, actors...)
	}
	return results, nil
}

func (c *clientWithFallback) IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error) {
	result, err := c.client.IsFeatureFlagEnabledForRepository(ctx, feature, repositoryID)
	if err != nil {
		contextlogger.Warn(ctx, "Failed to check feature flag for repository, falling back to fallback client",
			kvp.String("feature_flag.key", feature),
			kvp.Uint64("gh.repo.id", repositoryID),
			kvp.String("exception.message", err.Error()),
		)
		return c.fallback.IsFeatureFlagEnabledForRepository(ctx, feature, repositoryID)
	}
	return result, nil
}

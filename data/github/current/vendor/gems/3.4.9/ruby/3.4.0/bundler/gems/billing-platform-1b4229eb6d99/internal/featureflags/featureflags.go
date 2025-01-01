package featureflags

// Vexi README: https://github.com/github/feature-management-client-go/blob/main/vexi/README.md

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/feature-management-client-go/vexi"
	ffd_adapter "github.com/github/feature-management-client-go/vexi/adapter/feature_flag_data"
	hydro_adapter "github.com/github/feature-management-client-go/vexi/adapter/hydro"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

func NewClient(ctx context.Context, cfg *config.Config, logger log.Logger, statter stats.Client) (*vexi.Client, error) {
	if !cfg.IsProduction() {
		return newDevClient(ctx, logger)
	}
	return newProductionClient(ctx, cfg, logger, statter)
}

func newDevClient(ctx context.Context, logger log.Logger) (*vexi.Client, error) {
	featureFlagDataAdapter, err := ffd_adapter.New(ffd_adapter.FeatureManagementLiteURL)
	if err != nil {
		return nil, fmt.Errorf("failed to build feature flag data adapter: %w", err)
	}

	client, err := vexi.NewClient(ctx,
		featureFlagDataAdapter,
		vexi.WithLogger(logger),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to build vexi client: %w", err)
	}
	return client, nil
}

func newProductionClient(ctx context.Context, cfg *config.Config, logger log.Logger, statter stats.Client) (*vexi.Client, error) {
	hydroAdapter, err := buildHydroAdapter(ctx, cfg, logger, statter)
	if err != nil {
		return nil, fmt.Errorf("failed to build hydro adapter: %w", err)
	}

	client, err := vexi.NewClient(ctx,
		hydroAdapter,
		vexi.WithLogger(logger),
		vexi.WithStatsClient(statter),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to build vexi client: %w", err)
	}
	return client, nil
}

func buildHydroAdapter(ctx context.Context, cfg *config.Config, logger log.Logger, statter stats.Client) (vexi.Adapter, error) {
	hydroBrokers := strings.Join(cfg.ParsedHydroKafkaBrokers(), ",")
	hydroAdapter, err := hydro_adapter.New(ctx,
		hydro_adapter.WithOwningService(cfg.ServiceName),
		hydro_adapter.WithLogger(logger),
		hydro_adapter.WithStatsClient(statter),
		hydro_adapter.WithHydroBrokers(hydroBrokers),
		hydro_adapter.WithSystemRootCA(),
		hydro_adapter.WithCuratedSegments(), // Optional, if you intend to evaluate staffshiped feature flags
	)
	if err != nil {
		return nil, fmt.Errorf("failed to build hydro adapter: %w", err)
	}

	cacheReady, err := hydroAdapter.Start(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to start hydro adapter: %w", err)
	}

	select {
	case <-cacheReady:
		return hydroAdapter, nil
	case <-time.After(5 * time.Second):
		// Timeout after 5 seconds
		return nil, fmt.Errorf("vexi hydro cache was not ready in available timeout window")
	}
}

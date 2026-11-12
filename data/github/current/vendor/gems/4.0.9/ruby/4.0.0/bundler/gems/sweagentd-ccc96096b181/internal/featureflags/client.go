// Package featureflags provides feature flag client functionality for sweagentd.
package featureflags

import (
	"context"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/github/feature-management-client-go/vexi/v2"
	hydro_adapter "github.com/github/feature-management-client-go/vexi/v2/adapter/hydro"
	"github.com/github/feature-management-client-go/vexi/v2/extensions"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-server/runtime/features"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

// Client is the interface for feature flag operations.
type Client interface {
	IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool
	IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool
	IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool
	IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool
	IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.Repository) bool
	IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool
	IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool
	IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool
}

// FeatureFlagClient is the main implementation of the Client interface.
type FeatureFlagClient struct {
	client features.Flagger
	obsv   observability.Exporters
	ready  atomic.Bool
}

// IsEnabled implements Client.
func (f *FeatureFlagClient) IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool {
	if !f.ready.Load() {
		f.obsv.Logger.Warn("feature flag client not ready, returning default value", kvp.String("feature_flag", featureFlagName))
		return false
	}

	return f.client.IsEnabledWithDefaultValue(ctx, featureFlagName, false, actors...)
}

// IsEnabledForUser checks if a feature flag is enabled for a specific user.
func (f *FeatureFlagClient) IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, extensions.NewUser(strconv.FormatInt(userID, 10)))
}

// IsEnabledForRepo checks if a feature flag is enabled for a specific repository.
func (f *FeatureFlagClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, extensions.NewRepository(strconv.FormatInt(repoID, 10)))
}

// IsEnabledForUserOrRepo checks if a feature flag is enabled for a user or repository.
func (f *FeatureFlagClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	actors := []vexi.Actor{
		extensions.NewUser(strconv.FormatInt(userID, 10)),
		extensions.NewRepository(strconv.FormatInt(repoID, 10)),
	}
	return f.IsEnabled(ctx, featureFlagName, actors...)
}

// IsEnabledForRepoOrOwner checks if a feature flag is enabled for a repository or repository owner using the sweagentd.Repository interface.
func (f *FeatureFlagClient) IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.Repository) bool {
	return f.IsEnabled(ctx, featureFlagName,
		extensions.NewRepository(strconv.FormatInt(actors.GetRepositoryID(), 10)),
		extensions.NewUser(strconv.FormatInt(actors.GetOwnerID(), 10)), // Owner as a user
		extensions.NewOrganization(strconv.FormatInt(actors.GetOwnerID(), 10)))
}

// IsEnabledForUserOrRepoOrOwner checks if a feature flag is enabled for a user, repository, or repository owner using the sweagentd.RepositoryWithActor interface.
func (f *FeatureFlagClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool {
	return f.IsEnabled(ctx, featureFlagName,
		extensions.NewUser(strconv.FormatInt(actors.GetActorID(), 10)),
		extensions.NewRepository(strconv.FormatInt(actors.GetRepositoryID(), 10)),
		extensions.NewUser(strconv.FormatInt(actors.GetOwnerID(), 10)), // Owner as a user
		extensions.NewOrganization(strconv.FormatInt(actors.GetOwnerID(), 10)))
}

// IsEnabledForGitHubApp checks if a feature flag is enabled for a specific GitHub App.
func (f *FeatureFlagClient) IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, extensions.NewGitHubApp(strconv.FormatInt(appID, 10)))
}

// IsEnabledForOAuthApp checks if a feature flag is enabled for a specific OAuth App.
func (f *FeatureFlagClient) IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, extensions.NewOAuthApplication(strconv.FormatInt(appID, 10)))
}

var _ Client = &FeatureFlagClient{}

// AdditionalOwningServices is a list of additional owning services for feature flags.
// These are in addition to the primary owning service (sweagentd).
var AdditionalOwningServices = []string{"copilot-coding-agent", "copilot-extensibility", "copilot-experiences-growth"}

// NewClient creates a new feature flag client.
func NewClient(ctx context.Context, cfg *config.Config, obsv observability.Exporters) (Client, error) {
	owningServices := append([]string{cfg.ServiceName}, AdditionalOwningServices...)
	hydroAdapter, err := hydro_adapter.NewAdapterWithOwningServices(ctx, cfg.ServiceName, owningServices,
		hydro_adapter.WithLogger(obsv.Logger.Named("vexi-hydro")),
		hydro_adapter.WithLogOnUpdate(), // Log each flag update
		hydro_adapter.WithStatsClient(obsv.Statter),
		hydro_adapter.WithHydroBrokers(strings.Join(cfg.HydroBrokers, ",")),
		hydro_adapter.WithCuratedSegments(),
	)
	if err != nil {
		return nil, goerrors.Errorf("creating hydro adapter: %w", err)
	}

	cacheReady, err := hydroAdapter.Start(ctx)
	if err != nil {
		return nil, goerrors.Errorf("starting hydro adapter: %w", err)
	}

	// Wait for cache to become ready
	ready := false
	select {
	case <-cacheReady:
		// Cache is ready
		ready = true
	case <-time.After(5 * time.Second):
		// Timeout after 5 seconds
		obsv.Logger.Warn("feature flag cache not ready after 5 seconds")
	}

	vexiClient, err := vexi.NewVexiClient(ctx,
		hydroAdapter,
		cfg.ServiceName,
		vexi.WithLogger(obsv.Logger.Named("vexi")),
		vexi.WithStatsClient(obsv.Statter),
	)
	if err != nil {
		return nil, goerrors.Errorf("creating vexi client: %w", err)
	}

	ffc := &FeatureFlagClient{
		client: vexiClient,
		obsv:   obsv.WithNamedLogger("feature-flags"),
	}

	if !ready {
		go func() {
			<-cacheReady
			ffc.obsv.Logger.Info("feature flag client is now ready")
			ffc.ready.Store(true)
		}()
	} else {
		ffc.ready.Store(true)
	}

	return ffc, nil
}

// NewClientWithExistingVexiClient creates a new feature flag client using an existing Vexi client.
func NewClientWithExistingVexiClient(flagger features.Flagger, obsv observability.Exporters) Client {
	ffc := &FeatureFlagClient{
		client: flagger,
		obsv:   obsv.WithNamedLogger("feature-flags"),
	}
	// The provided flagger is already cacheReady
	ffc.ready.Store(true)
	return ffc
}

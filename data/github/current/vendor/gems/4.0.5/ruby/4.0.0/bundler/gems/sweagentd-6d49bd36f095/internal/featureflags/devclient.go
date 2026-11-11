package featureflags

import (
	"context"
	"fmt"

	"github.com/github/feature-management-client-go/vexi/v2"
	ffd_adapter "github.com/github/feature-management-client-go/vexi/v2/adapter/feature_flag_data"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

// DevClient is a development feature flag client implementation.
type DevClient struct {
	client *vexi.Client
}

// NewDevClient creates a new development feature flag client.
func NewDevClient(ctx context.Context, serviceName string, obsv observability.Exporters) (*DevClient, error) {
	featureFlagDataAdapter, err := ffd_adapter.New(ffd_adapter.FeatureManagementLiteURL)
	if err != nil {
		return nil, goerrors.Errorf("creating feature flag data adapter: %w", err)
	}

	vexiClient, err := vexi.NewVexiClient(ctx, featureFlagDataAdapter, serviceName, vexi.WithLogger(obsv.Logger))
	if err != nil {
		return nil, goerrors.Errorf("creating vexi client: %w", err)
	}

	return &DevClient{client: vexiClient}, nil
}

// IsEnabled checks if a feature flag is enabled using the development client.
func (f *DevClient) IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool {
	return f.IsEnabledWithDefaultValue(ctx, featureFlagName, false, actors...)
}

// IsEnabledWithDefaultValue checks if a feature flag is enabled with a fallback default.
func (f *DevClient) IsEnabledWithDefaultValue(ctx context.Context, featureFlagName string, defaultValue bool, actors ...vexi.Actor) bool {
	return f.client.IsEnabledWithDefaultValue(ctx, featureFlagName, defaultValue, actors...)
}

// IsEnabledForUser checks if a feature flag is enabled for a specific user using the development client.
func (f *DevClient) IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, vexi.NewActor(fmt.Sprintf("User:%d", userID)))
}

// IsEnabledForRepo checks if a feature flag is enabled for a specific repository using the development client.
func (f *DevClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, vexi.NewActor(fmt.Sprintf("Repository:%d", repoID)))
}

// IsEnabledForUserOrRepo checks if a feature flag is enabled for a user or repository using the development client.
func (f *DevClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, vexi.NewActor(fmt.Sprintf("User:%d", userID)), vexi.NewActor(fmt.Sprintf("Repository:%d", repoID)))
}

// IsEnabledForOrganization checks if a feature flag is enabled for a specific organization using the development client.
func (f *DevClient) IsEnabledForOrganization(ctx context.Context, featureFlagName string, orgID int64) bool {
	orgActor := vexi.NewActor(fmt.Sprintf("Organization:%d", orgID))
	return f.IsEnabled(ctx, featureFlagName, orgActor)
}

// IsEnabledForOwner checks if a feature flag is enabled for a repository owner using the development client.
func (f *DevClient) IsEnabledForOwner(ctx context.Context, featureFlagName string, ownerID int64) bool {
	ownerActor := vexi.NewActor(fmt.Sprintf("User:%d", ownerID))
	orgOwnerActor := vexi.NewActor(fmt.Sprintf("Organization:%d", ownerID))
	return f.IsEnabled(ctx, featureFlagName, ownerActor, orgOwnerActor)
}

// IsEnabledForRepoOrOwner checks if a feature flag is enabled for a repository or its owner using the development client.
func (f *DevClient) IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.Repository) bool {
	return f.IsEnabledForRepoOrOwnerWithDefaultValue(ctx, featureFlagName, false, actors)
}

// IsEnabledForRepoOrOwnerWithDefaultValue checks a repository or owner feature flag with a fallback default.
func (f *DevClient) IsEnabledForRepoOrOwnerWithDefaultValue(ctx context.Context, featureFlagName string, defaultValue bool, actors sweagentd.Repository) bool {
	repoActor := vexi.NewActor(fmt.Sprintf("Repository:%d", actors.GetRepositoryID()))
	ownerActor := vexi.NewActor(fmt.Sprintf("User:%d", actors.GetOwnerID()))
	orgOwnerActor := vexi.NewActor(fmt.Sprintf("Organization:%d", actors.GetOwnerID()))
	return f.IsEnabledWithDefaultValue(ctx, featureFlagName, defaultValue, repoActor, ownerActor, orgOwnerActor)
}

// IsEnabledForUserOrRepoOrOwner checks if a feature flag is enabled for a user, repository, or repository owner using the sweagentd.RepositoryWithActor interface.
func (f *DevClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool {
	userActor := vexi.NewActor(fmt.Sprintf("User:%d", actors.GetActorID()))
	repoActor := vexi.NewActor(fmt.Sprintf("Repository:%d", actors.GetRepositoryID()))
	ownerActor := vexi.NewActor(fmt.Sprintf("User:%d", actors.GetOwnerID()))
	orgOwnerActor := vexi.NewActor(fmt.Sprintf("Organization:%d", actors.GetOwnerID()))
	return f.IsEnabled(ctx, featureFlagName, userActor, repoActor, ownerActor, orgOwnerActor)
}

// IsEnabledForGitHubApp checks if a feature flag is enabled for a specific GitHub App using the development client.
func (f *DevClient) IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool {
	// https://github.com/github/feature-management-client-go/blob/0b84383f18b3cb11a97eb3e0119a311b7786dc57/vexi/extensions/actor.go#L56
	return f.IsEnabled(ctx, featureFlagName, vexi.NewActor(fmt.Sprintf("Integration:%d", appID)))
}

// IsEnabledForOAuthApp checks if a feature flag is enabled for a specific OAuth App using the development client.
func (f *DevClient) IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool {
	// https://github.com/github/feature-management-client-go/blob/0b84383f18b3cb11a97eb3e0119a311b7786dc57/vexi/extensions/actor.go#L51
	return f.IsEnabled(ctx, featureFlagName, vexi.NewActor(fmt.Sprintf("OauthApplication:%d", appID)))
}

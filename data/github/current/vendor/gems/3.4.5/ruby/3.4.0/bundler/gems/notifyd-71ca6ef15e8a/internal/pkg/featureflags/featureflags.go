/*
Package featureflags allows you to check whether a single
feature flag is enabled for a user, a group of users, or everyone.

Note: that this package makes a network request to the monolith via the Twirp API.

Example usage:

	featureflags := featureflags.NewClient(context.Context)

	// To check if a feature is globally enabled:
	featureflags.IsEnabled(context.Context, "feature-name")

	// To check if a feature is enabled for a specific actor:
	featureflags.IsEnabledForActor(context.Context, "feature-name", "User:1")

	// To check if a feature is enabled for a number of actors:
	featureflags.IsEnabledForActors(context.Context, "feature-name", []string{"User:1", "User:2"})
*/
package featureflags

import (
	"context"

	features "github.com/github/monolith-twirp-features/core/v1"
)

// Client has some helper methods that Notifyd uses a lot to check for feature flags.
type Client interface {
	IsEnabled(ctx context.Context, feature string) (bool, error)
	IsEnabledForActor(ctx context.Context, feature string, userID int64) (bool, error)
	IsEnabledForActors(ctx context.Context, feature string, userIDs []int64) (map[string]bool, error)
}

// featuresClient exists so we can run tests using a FeaturesAPI client mock
type featuresClient interface { //nolint:unused // used in tests
	features.FeaturesAPI
}

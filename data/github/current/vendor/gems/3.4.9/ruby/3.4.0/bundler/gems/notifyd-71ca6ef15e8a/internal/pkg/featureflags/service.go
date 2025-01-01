package featureflags

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-twirp/v2/client/auth"
	"github.com/github/go-twirp/v2/client/requestid"
	features "github.com/github/monolith-twirp-features/core/v1"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/http"
)

// DotcomClient is a type that implements the FeaturesAPI. It has useful
// methods that abstract the Twirp client specifics away from the caller.
type DotcomClient struct {
	features.FeaturesAPI
}

// NewClient returns a configured Client.
func NewClient(url, key string, logger log.Logger) (*DotcomClient, error) {
	// Our research shows that the checks we do take at max 6 seconds, so we give it a bit of margin
	// but make sure we timeout if they get out of hand.
	requestIDClient := requestid.NewForwarder(
		http.NewClient(
			http.WithRetryTimeout(8*time.Second),
			http.WithLogger(logger),
		),
	)

	twirpClient, err := auth.NewRequestHMACSigner(key, requestIDClient)
	if err != nil {
		return &DotcomClient{}, errors.Wrap(err, "initializing RequestHMACSigner")
	}

	return &DotcomClient{
		FeaturesAPI: features.NewFeaturesAPIProtobufClient(url, twirpClient),
	}, nil
}

// IsEnabled checks if a feature is enabled globally. Returns a Boolean.
func (c *DotcomClient) IsEnabled(ctx context.Context, feature string) (bool, error) {
	req := features.CheckGlobalFeatureRequest{Feature: feature}
	resp, err := c.CheckGlobalFeature(ctx, &req)
	if err != nil {
		return false, errors.Wrap(err, "features.CheckGlobalFeatureRequest")
	}

	return resp.IsEnabled, nil
}

// IsEnabledForActor checks if a feature is enabled for the specified actorId. Returns a Boolean.
func (c *DotcomClient) IsEnabledForActor(ctx context.Context, feature string, userID int64) (bool, error) {
	req := features.CheckActorFeatureRequest{Feature: feature, ActorId: userIDToActorID(userID)}
	resp, err := c.CheckActorFeature(ctx, &req)
	if err != nil {
		return false, errors.Wrap(err, "features.CheckActorFeature")
	}

	return resp.IsEnabled, nil
}

// IsEnabledForActors checks if a feature is enabled for a list of actorIds. Returns a map of actorIds to booleans.
func (c *DotcomClient) IsEnabledForActors(ctx context.Context, feature string, userIDs []int64) (map[string]bool, error) {
	actorIDs := make([]string, len(userIDs))
	for i, userID := range userIDs {
		actorIDs[i] = userIDToActorID(userID)
	}

	req := features.CheckActorsFeatureRequest{Feature: feature, ActorIds: actorIDs}
	resp, err := c.CheckActorsFeature(ctx, &req)
	if err != nil {
		return nil, errors.Wrap(err, "features.CheckActorsFeature")
	}

	result := make(map[string]bool, len(resp.Results))
	for _, actorFeatureResult := range resp.Results {
		result[actorFeatureResult.ActorId] = actorFeatureResult.IsEnabled
	}

	return result, nil
}

func userIDToActorID(id int64) string {
	return fmt.Sprintf("User:%d", id)
}

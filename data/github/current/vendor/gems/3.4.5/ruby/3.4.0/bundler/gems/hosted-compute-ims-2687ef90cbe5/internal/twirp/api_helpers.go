package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
)

func (h *baseApiHandler) isCuratedImageDefinitionEnabledForActor(ctx context.Context, imageDefinition *models.ImageDefinition, actor *sharedapi.Actor) bool {
	if imageDefinition.FeatureFlag != nil && *imageDefinition.FeatureFlag != "" {
		actor, err := actorFromTwirpActor(actor)
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to check if image definition is enabled for actor. Falling back to false value", err, kvp.String("feature_flag", *imageDefinition.FeatureFlag))
			return false
		}
		return featureflags.IsFeatureFlagEnabledForActor(ctx, featureflags.FeatureFlag(*imageDefinition.FeatureFlag), actor)
	}
	return imageDefinition.Enabled
}

func (h *baseApiHandler) getCustomerImageDefinitionsLimitForActor(ctx context.Context, twirpActor *sharedapi.Actor) int {
	const (
		imageDefinitionsLimitDefault   = 50
		imageDefinitionsLimitIncreased = 250
	)

	actor, err := actorFromTwirpActor(twirpActor)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to check image definitions limit increase eligibility for actor. Falling back to default limit", err)
		return imageDefinitionsLimitDefault
	}

	if featureflags.IsFeatureFlagEnabledForActor(ctx, featureflags.FeatureFlag_CustomerImageDefinitionsLimitIncrease, actor) {
		return imageDefinitionsLimitIncreased
	}

	return imageDefinitionsLimitDefault
}

func (h *baseApiHandler) getCustomerImageVersionsLimitForActor(ctx context.Context, twirpActor *sharedapi.Actor) int32 {
	const (
		imageVersionsPerDefinitionLimitDefault   = 50
		imageVersionsPerDefinitionLimitIncreased = 250
	)

	actor, err := actorFromTwirpActor(twirpActor)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to check image versions limit increase eligibility for actor. Falling back to default limit", err)
		return imageVersionsPerDefinitionLimitDefault
	}

	if featureflags.IsFeatureFlagEnabledForActor(ctx, featureflags.FeatureFlag_CustomerImageVersionsLimitIncrease, actor) {
		return imageVersionsPerDefinitionLimitIncreased
	}

	return imageVersionsPerDefinitionLimitDefault
}

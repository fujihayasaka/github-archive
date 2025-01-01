package featureflags

import (
	"context"
	"slices"

	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/utils"
)

var _ IFeatureFlagsClient = (*localClient)(nil)

type localClient struct {
	flagsGlobal   map[FeatureFlag]bool
	flagsPerActor map[FeatureFlag][]string
}

func newLocalClient() *localClient {
	return &localClient{
		flagsGlobal:   map[FeatureFlag]bool{},
		flagsPerActor: map[FeatureFlag][]string{},
	}
}

func newLocalClientFromConfig(ctx context.Context) *localClient {
	type localFeaturesConfig struct {
		EnabledGlobally []FeatureFlag `yaml:"enabledGlobally"`
		EnabledPerActor []struct {
			Flag  FeatureFlag `yaml:"flag"`
			Actor string      `yaml:"actor"`
		} `yaml:"enabledPerActor"`
	}

	localConfig, err := utils.GetDevConfig[localFeaturesConfig]("feature-flags.yml")
	if err != nil {
		logger.WithError(err).Error(ctx, "failed to read local feature flags config file")
		localConfig = &localFeaturesConfig{}
	}

	client := newLocalClient()
	for _, flagName := range localConfig.EnabledGlobally {
		client.EnableFeatureFlagGlobally(flagName)
	}
	for _, flagObj := range localConfig.EnabledPerActor {
		client.EnableFeatureFlagForActor(flagObj.Flag, flagObj.Actor)
	}

	return client
}

func (c *localClient) IsFeatureFlagEnabledGlobally(ctx context.Context, feature FeatureFlag) bool {
	if _, ok := c.flagsGlobal[feature]; ok {
		return true
	}

	return false
}

func (c *localClient) IsFeatureFlagEnabledForActor(ctx context.Context, feature FeatureFlag, actor vexi.Actor) bool {
	if actor == nil {
		logger.Error(ctx, "actor is nil, cannot check feature flag, defaulting false")
		return false
	}

	if _, ok := c.flagsGlobal[feature]; ok {
		return true
	}

	if enabledOwners, ok := c.flagsPerActor[feature]; ok {
		for _, enabledOwner := range enabledOwners {
			if enabledOwner == actor.VexiID() {
				return true
			}
		}
	}

	return false
}

func (c *localClient) EnableFeatureFlagGlobally(feature FeatureFlag) *localClient {
	c.flagsGlobal[feature] = true

	return c
}

func (c *localClient) DisableFeatureFlagGlobally(feature FeatureFlag) *localClient {
	delete(c.flagsGlobal, feature)

	return c
}

func (c *localClient) EnableFeatureFlagForActor(feature FeatureFlag, actor string) *localClient {
	if _, ok := c.flagsPerActor[feature]; !ok {
		c.flagsPerActor[feature] = []string{}
	}
	c.flagsPerActor[feature] = append(c.flagsPerActor[feature], actor)

	return c
}

func (c *localClient) DisableFeatureFlagForActor(feature FeatureFlag, actor string) *localClient {
	if _, ok := c.flagsPerActor[feature]; ok {
		c.flagsPerActor[feature] = slices.DeleteFunc(c.flagsPerActor[feature], func(owner string) bool { return owner == actor })
		if len(c.flagsPerActor[feature]) == 0 {
			delete(c.flagsPerActor, feature)
		}
	}

	return c
}

func (c *localClient) Reset() {
	c.flagsGlobal = map[FeatureFlag]bool{}
	c.flagsPerActor = map[FeatureFlag][]string{}
}

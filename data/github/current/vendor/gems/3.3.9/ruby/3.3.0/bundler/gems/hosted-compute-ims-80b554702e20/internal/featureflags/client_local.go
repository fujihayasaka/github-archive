package featureflags

import (
	"context"
	"slices"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/utils"
)

type localClient struct {
	Logger        *telemetry.ReportingLogger
	flagsGlobal   map[FeatureFlag]bool
	flagsPerOwner map[FeatureFlag][]string
}

func newLocalClient(logger *telemetry.ReportingLogger) *localClient {
	return &localClient{
		Logger:        logger,
		flagsGlobal:   map[FeatureFlag]bool{},
		flagsPerOwner: map[FeatureFlag][]string{},
	}
}

func newLocalClientFromConfig(logger *telemetry.ReportingLogger) *localClient {
	type localFeaturesConfig struct {
		EnabledGlobally []FeatureFlag `yaml:"enabledGlobally"`
		EnabledPerOwner []struct {
			Flag  FeatureFlag `yaml:"flag"`
			Owner string      `yaml:"owner"`
		} `yaml:"enabledPerOwner"`
	}

	localConfig, err := utils.GetDevConfig[localFeaturesConfig]("feature-flags.yml")
	if err != nil {
		logger.WithError(err).Error("failed to read local feature flags config file")
		localConfig = &localFeaturesConfig{}
	}

	client := newLocalClient(logger)
	for _, flagName := range localConfig.EnabledGlobally {
		client.EnableFeatureFlagGlobally(flagName)
	}
	for _, flagObj := range localConfig.EnabledPerOwner {
		client.EnableFeatureFlagForOwner(flagObj.Flag, flagObj.Owner)
	}

	return client
}

func (c *localClient) IsFeatureFlagEnabledGlobally(ctx context.Context, feature FeatureFlag) bool {
	if _, ok := c.flagsGlobal[feature]; ok {
		return true
	}

	return false
}

func (c *localClient) IsFeatureFlagEnabledForActor(ctx context.Context, feature FeatureFlag, ownerId string) bool {
	if _, ok := c.flagsGlobal[feature]; ok {
		return true
	}

	if enabledOwners, ok := c.flagsPerOwner[feature]; ok {
		for _, enabledOwner := range enabledOwners {
			if enabledOwner == ownerId {
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

func (c *localClient) EnableFeatureFlagForOwner(feature FeatureFlag, ownerId string) *localClient {
	if _, ok := c.flagsPerOwner[feature]; !ok {
		c.flagsPerOwner[feature] = []string{}
	}
	c.flagsPerOwner[feature] = append(c.flagsPerOwner[feature], ownerId)

	return c
}

func (c *localClient) DisableFeatureFlagForOwner(feature FeatureFlag, ownerId string) *localClient {
	if _, ok := c.flagsPerOwner[feature]; ok {
		c.flagsPerOwner[feature] = slices.DeleteFunc(c.flagsPerOwner[feature], func(owner string) bool { return owner == ownerId })
		if len(c.flagsPerOwner[feature]) == 0 {
			delete(c.flagsPerOwner, feature)
		}
	}

	return c
}

func (c *localClient) Reset() {
	c.flagsGlobal = map[FeatureFlag]bool{}
	c.flagsPerOwner = map[FeatureFlag][]string{}
}

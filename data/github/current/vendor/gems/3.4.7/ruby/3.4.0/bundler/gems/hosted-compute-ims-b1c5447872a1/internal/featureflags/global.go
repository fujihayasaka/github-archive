package featureflags

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
)

var (
	globalClientDefaultKey = "default"
	globalClientsPerStamp  = map[string]IFeatureFlagsClient{}
)

func SetupNewGlobalFeatureFlagsClient(ctx context.Context, cfg *Config, logger *telemetry.ReportingLogger) error {
	if len(cfg.SupportedStamps) == 0 {
		return fmt.Errorf("no supported stamps for feature flags client are defined")
	}

	defaultStamp := cfg.SupportedStamps[0]

	for _, stamp := range cfg.SupportedStamps {
		client, err := NewFeatureFlagsClient(ctx, cfg, logger, stamp)
		if err != nil {
			return err
		}

		globalClientsPerStamp[stamp] = client
	}

	globalClientsPerStamp[globalClientDefaultKey] = globalClientsPerStamp[defaultStamp]

	return nil
}

func IsFeatureFlagEnabledGlobally(ctx context.Context, feature FeatureFlag) bool {
	if client, found := globalClientsPerStamp[globalClientDefaultKey]; found {
		return client.IsFeatureFlagEnabledGlobally(ctx, feature)
	} else {
		panic("global feature flags client is not configured")
	}
}

func IsFeatureFlagEnabledForActor(ctx context.Context, feature FeatureFlag, actor *models.Actor) bool {
	actorStamp := actor.Stamp
	if actorStamp == "" {
		// if stamp of actor is not defined explicitly, use default stamp
		actorStamp = globalClientDefaultKey
	}

	if client, found := globalClientsPerStamp[actorStamp]; found {
		return client.IsFeatureFlagEnabledForActor(ctx, feature, actor.GlobalId)
	} else {
		return false
	}
}

func TEST_SetupFeatureFlagsClient(t *testing.T) *localClient {
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)
	client := newLocalClient(logger)

	globalClientsPerStamp[globalClientDefaultKey] = client

	t.Cleanup(func() {
		globalClientsPerStamp[globalClientDefaultKey] = nil
	})

	return client
}

func TEST_GetFeatureFlagsClient() *localClient {
	if globalClientsPerStamp[globalClientDefaultKey] == nil {
		panic("test feature flags client is not configured. Did you forget to call TEST_SetupFeatureFlagsClient?")
	}

	if testClient, ok := globalClientsPerStamp[globalClientDefaultKey].(*localClient); ok {
		return testClient
	} else {
		panic("global feature flags client is not test client")
	}
}

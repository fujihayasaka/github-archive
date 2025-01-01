package featureflags

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
)

var globalClient IFeatureFlagsClient

func SetupNewGlobalFeatureFlagsClient(ctx context.Context, cfg *Config, logger *telemetry.ReportingLogger) error {
	client, err := NewFeatureFlagsClient(ctx, cfg, logger)
	if err != nil {
		return err
	}

	globalClient = client

	return nil
}

func IsFeatureFlagEnabledGlobally(ctx context.Context, feature FeatureFlag) bool {
	if globalClient == nil {
		panic("global feature flags client is not configured")
	}

	return globalClient.IsFeatureFlagEnabledGlobally(ctx, feature)
}

func IsFeatureFlagEnabledForActor(ctx context.Context, feature FeatureFlag, ownerId string) bool {
	if globalClient == nil {
		panic("global feature flags client is not configured")
	}

	return globalClient.IsFeatureFlagEnabledForActor(ctx, feature, ownerId)
}

func TEST_SetupFeatureFlagsClient(t *testing.T) *localClient {
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)
	client := newLocalClient(logger)

	globalClient = client

	t.Cleanup(func() {
		globalClient = nil
	})

	return client
}

func TEST_GetFeatureFlagsClient() *localClient {
	if globalClient == nil {
		panic("test feature flags client is not configured. Did you forget to call TEST_SetupFeatureFlagsClient?")
	}

	if testClient, ok := globalClient.(*localClient); ok {
		return testClient
	} else {
		panic("global feature flags client is not test client")
	}
}

package featureflags

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/github/feature-management-client-go/vexi"
	ffd_adapter "github.com/github/feature-management-client-go/vexi/adapter/feature_flag_data"
	hydro_adapter "github.com/github/feature-management-client-go/vexi/adapter/hydro"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
)

// imsVexiCanaryFlag is a feature flag which should always be enabled
// the client uses this to validate that the vexi system is working correctly
const (
	imsVexiCanaryFlag = "ims_vexi_feature_flag_canary"
	imsVexiAppName    = "hosted-compute-ims"
)

var owningServicesToSubscribe = []string{imsVexiAppName, "github/hosted_runners"}

type vexiClient struct {
	adapter                vexi.Adapter
	cfg                    *Config
	vexiClient             *vexi.Client
	waitForFlagStateToLoad *sync.WaitGroup
	featuresHydrated       bool
	waitExpired            bool
	initializeSuccess      bool
}

var _ IFeatureFlagsClient = (*vexiClient)(nil)

func newVexiClient(ctx context.Context, cfg *Config, stamp string) (*vexiClient, error) {
	if stamp != "dotcom" {
		panic("vexi client is only supported for dotcom stamp in ims at the moment")
	}

	var vexiAdapter vexi.Adapter
	var err error

	// Hydrate the feature flags in the background so we don't block startup
	// If code attempts to use the feature flags before they are hydrated
	// it will block via the waitgroup until timeout or hydration completes
	waitForHydrated := sync.WaitGroup{}
	featuresHydrated := false

	if cfg.HasLocalFFLite() {
		logger.Info(ctx, "initializing vexi client with ffd adapter")
		vexiAdapter, err = ffd_adapter.New(cfg.VexiFFLiteUrl)
		if err != nil {
			panic(err)
		}
		featuresHydrated = true
	} else {
		logger.Info(ctx, "initializing vexi client with hydro adapter")
		vexiAdapter, err = hydro_adapter.NewAdapterWithOwningServices(ctx,
			imsVexiAppName,
			owningServicesToSubscribe,
			hydro_adapter.WithLogger(logger.GetBaseLogger().Named("vexi-hydro-adapter")),
			hydro_adapter.WithStatsClient(statter.GetBaseStatter()),
			hydro_adapter.WithHydroBrokers(cfg.VexiHydroBrokers),
			hydro_adapter.WithRootCA(cfg.VexiHydroRootCA),
			hydro_adapter.WithCuratedSegments(),
		)
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to create vexi hydro adapter", err)
			return nil, fmt.Errorf("failed to create vexi hydro adapter: %w", err)
		}

		// wait until the feature flags are hydrated
		waitForHydrated.Add(1)
	}

	vexi, err := vexi.NewVexiClient(ctx,
		vexiAdapter,
		imsVexiAppName,
		vexi.WithLogger(logger.GetBaseLogger().Named("vexi-client")),
		vexi.WithStatsClient(statter.GetBaseStatter()),
		vexi.WithSampling(vexi.SamplingRate01Percent),
	)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to create vexi client", err)
		return nil, fmt.Errorf("failed to create vexi client: %w", err)
	}

	vexiClient := &vexiClient{
		adapter:                vexiAdapter,
		cfg:                    cfg,
		vexiClient:             vexi,
		waitForFlagStateToLoad: &waitForHydrated,
		featuresHydrated:       featuresHydrated,
		initializeSuccess:      true,
	}

	vexiClient.setupVexiAdapterInBackground(ctx)

	return vexiClient, nil
}

func (c *vexiClient) setupVexiAdapterInBackground(ctx context.Context) {
	go func() {
		switch adapter := c.adapter.(type) {
		case *ffd_adapter.Adapter:
			c.logIfVexiDataCorrect(ctx)
			return
		case *hydro_adapter.Adapter:
			resilientlyHandleHydroAdapterSetup(ctx, adapter, c)
		default:
			return
		}
	}()
}

func (c *vexiClient) IsFeatureFlagEnabledGlobally(ctx context.Context, feature FeatureFlag) bool {
	waitForFlagHydrationIfNeeded(ctx, c)

	// Return the flag result or `false` for the default value, if hydro is broken
	return c.vexiClient.IsEnabledWithDefaultValue(ctx, string(feature), false)
}

func (c *vexiClient) IsFeatureFlagEnabledForActor(ctx context.Context, feature FeatureFlag, actor vexi.Actor) bool {
	if actor == nil {
		logger.Error(ctx, "actor is nil, cannot check feature flag, defaulting false")
		return false
	}

	waitForFlagHydrationIfNeeded(ctx, c)

	// Return the flag result or `false` for the default value, if hydro is broken
	// Note: This call will handle global or actor level enablement (unlike twirp) so we don't need to check both
	return c.vexiClient.IsEnabledWithDefaultValue(ctx, string(feature), false, actor)
}

func waitForFlagHydrationIfNeeded(ctx context.Context, c *vexiClient) {
	if c.featuresHydrated {
		return
	}

	// This will complete after hydro is synced or we timeout waiting for hydro to sync
	// the feature flag data
	//
	// Isn't it expensive to always wait? No. Wait is 63ns slower than a boolean check
	// that's 0.000063 milliseconds. We can afford that.

	// From benchmark
	//	 cpu: AMD EPYC 7763 64-Core Processor
	//	 BenchmarkWaitGroupVsBoolean
	//	 BenchmarkWaitGroupVsBoolean/WaitGroup
	//	 BenchmarkWaitGroupVsBoolean/WaitGroup-32                1000000000             129.9 ns/op
	//	 BenchmarkWaitGroupVsBoolean/BooleanCheck
	//	 BenchmarkWaitGroupVsBoolean/BooleanCheck-32             1000000000              66.90 ns/op
	c.waitForFlagStateToLoad.Wait()

	// Check again as feature data may now be hydrated
	if c.featuresHydrated {
		return
	}

	if c.waitExpired {
		logger.Warn(ctx, "vexi client is not hydrated, flag will return default value")
		return
	}
}

// The canary flag should always be enabled
// we then use it to validate the vexi system is working correctly
func (c *vexiClient) logIfVexiDataCorrect(ctx context.Context) bool {
	available, err := c.vexiClient.IsEnabledWithError(ctx, imsVexiCanaryFlag)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed making feature flag check with vexi", err)
		statter.Increment(ctx, "vexi_api.inaccurate_data")
		return false
	}

	logger.Info(ctx, "vexi data check",
		kvp.String("feature_flag", imsVexiCanaryFlag),
		kvp.Bool("result", available),
	)

	if !available {
		statter.Increment(ctx, "vexi_api.inaccurate_data")
		logger.Warn(ctx, "vexi data is not accurate")
	}

	return available
}

func resilientlyHandleHydroAdapterSetup(ctx context.Context, hydroAdapter *hydro_adapter.Adapter, c *vexiClient) {
	startTime := time.Now()
	setupBackoff := 20 * time.Millisecond
	setupMaxBackOffTime := 45 * time.Second

	// Try and start the hydro adapter, retrying if it fails
	var hydroFeaturesRead <-chan struct{}
	for {
		cacheReady, err := hydroAdapter.Start(ctx)
		if err == nil {
			// Start of the hydro adapter was successful
			// Now we can wait on it to read all the flags from hydro
			hydroFeaturesRead = cacheReady
			break
		} else {
			// Failed to start hydro adapter
			logger.WithError(err).Error(ctx, "failed to start vexi hydro adapter, retrying...")

			if time.Since(startTime) > time.Duration(c.cfg.VexiHydroInitTimeoutSec)*time.Second {
				// If we've exceeded the timeout, allow flags to be read with default value
				c.waitExpired = true
				c.waitForFlagStateToLoad.Done()

				logger.Warn(ctx, "exceeded vexi hydro init timeout, features will default to false")
				return
			}

			// Backoff before retrying
			time.Sleep(setupBackoff)
			if setupBackoff < setupMaxBackOffTime {
				setupBackoff *= 2
			}
			statter.Increment(ctx, "vexi_hydro.startup_error")
		}
	}

	statter.DistributionMs(ctx, "vexi_hydro.startup_time", time.Since(startTime))

	// Wait for the hydro adapter to read feature flag data from cache
	remainingTimeout := time.Duration(c.cfg.VexiHydroInitTimeoutSec)*time.Second - time.Since(startTime)
	select {
	case <-hydroFeaturesRead: // Cache is ready! Unblock feature flag calls
		// Allow ff calls to proceed
		c.featuresHydrated = true
		c.logIfVexiDataCorrect(ctx)
		c.waitForFlagStateToLoad.Done()
	case <-time.After(remainingTimeout): // Cache is not ready, but we've hit the timeout. Unblock feature flag calls defaulting false.
		err := fmt.Errorf("vexi hydro cache was not ready in available timeout window. Flags will default false!")
		logger.WithError(err).Error(ctx, "Flags will default false! Failed to start vexi hydro adapter")
		statter.Increment(ctx, "vexi_hydro_cache.not_ready")

		// Allow ff's to respond with default of false, even though hydro is not ready.
		c.waitExpired = true
		c.waitForFlagStateToLoad.Done()

		// We hit the timeout but the hydro adapter will hopefully sync eventually so keep tracking that.
		// Update the state once the cache is ready and start using the real flag values
		select {
		case <-hydroFeaturesRead:
			c.featuresHydrated = true
			c.logIfVexiDataCorrect(ctx)
			logger.Info(ctx, "vexi hydro cache is now ready, after delay")
		case <-ctx.Done():
			logger.Warn(ctx, "context cancelled while waiting for hydro features to be read")
		}
	}
}

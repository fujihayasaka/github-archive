package featureflags

import (
	"context"
	"reflect"
	"testing"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

func TestInitializer(t *testing.T) {
	logger := log.NewNullLogger()

	t.Run("FeatureFlagClient returns pointer to new client", func(t *testing.T) {
		got, _ := NewClient(context.Background(), &config.Config{}, logger, stats.NullStatter)
		gotType := reflect.TypeOf(got)
		if gotType != reflect.TypeOf(&vexi.Client{}) {
			t.Errorf("expected vexi.Client, got %v", gotType)
		}
	})
}

func Test_FeatureFlagStates(t *testing.T) {
	t.Run("returns false when feature is does NOT exist", func(t *testing.T) {
		featureName := "feature"
		ctx := context.Background()
		featuresAPI, _ := helpers.NewFeatureFlagClient(ctx, t, false)

		enabled := featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != false {
			t.Errorf("Expected flag to be false but got %v", enabled)
		}
	})

	t.Run("returns false when feature exists but NOT enabled", func(t *testing.T) {
		featureName := "feature"
		ctx := context.Background()
		featuresAPI, vexiFakeAdapter := helpers.NewFeatureFlagClient(ctx, t, false)

		vexiFakeAdapter.AddFeatureFlag(featureName, false)

		enabled := featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != false {
			t.Errorf("Expected flag to be false but got %v", enabled)
		}
	})

	t.Run("returns false when feature exists but enabled for different actors", func(t *testing.T) {
		featureName := "feature"
		ctx := context.Background()
		featuresAPI, vexiFakeAdapter := helpers.NewFeatureFlagClient(ctx, t, false)

		vexiFakeAdapter.AddFeatureFlag(featureName, false)
		vexiFakeAdapter.AddActors(featureName, []string{"Customer:111", "Customer:100"})

		enabled := featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != false {
			t.Errorf("Expected flag to be false but got %v", enabled)
		}
	})

	t.Run("returns true when feature exists AND enabled for the given actor", func(t *testing.T) {
		featureName := "feature"
		ctx := context.Background()
		featuresAPI, vexiFakeAdapter := helpers.NewFeatureFlagClient(ctx, t, false)

		vexiFakeAdapter.AddFeatureFlag(featureName, false)
		vexiFakeAdapter.AddActors(featureName, []string{"Customer:111", "Customer:123"})

		enabled := featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != true {
			t.Errorf("Expected flag to be true but got %v", enabled)
		}
	})

	t.Run("returns true when feature is enabled globally", func(t *testing.T) {
		featureName := "feature"
		ctx := context.Background()
		featuresAPI, vexiFakeAdapter := helpers.NewFeatureFlagClient(ctx, t, false)

		vexiFakeAdapter.AddFeatureFlag(featureName, true) // creates and enables globally

		enabled := featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != true {
			t.Errorf("Expected flag to be true but got %v", enabled)
		}
	})

	t.Run("returns false  if flag was once enabled for actor and then actor is removed", func(t *testing.T) {
		featureName := "feature"
		ctx := context.Background()
		featuresAPI, vexiFakeAdapter := helpers.NewFeatureFlagClient(ctx, t, false)

		vexiFakeAdapter.AddFeatureFlag(featureName, false)
		vexiFakeAdapter.AddActors(featureName, []string{"Customer:111", "Customer:123"})

		enabled := featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != true {
			t.Errorf("Expected flag to be true but got %v", enabled)
		}

		vexiFakeAdapter.RemoveActors(featureName, []string{"Customer:123"})

		enabled = featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != false {
			t.Errorf("Expected flag to be true but got %v", enabled)
		}
	})

	t.Run("returns false if flag was once globally enabled and then disabled globally", func(t *testing.T) {
		featureName := "feature"
		ctx := context.Background()
		featuresAPI, vexiFakeAdapter := helpers.NewFeatureFlagClient(ctx, t, false)

		vexiFakeAdapter.AddFeatureFlag(featureName, true)

		enabled := featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != true {
			t.Errorf("Expected flag to be true but got %v", enabled)
		}

		vexiFakeAdapter.DisableFeatureFlag(featureName)

		enabled = featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != false {
			t.Errorf("Expected flag to be true but got %v", enabled)
		}
	})

	t.Run("returns false if flag was once enabled for actor and then flag is deleted", func(t *testing.T) {
		featureName := "feature"
		ctx := context.Background()
		featuresAPI, vexiFakeAdapter := helpers.NewFeatureFlagClient(ctx, t, false)

		vexiFakeAdapter.AddFeatureFlag(featureName, false)
		vexiFakeAdapter.AddActors(featureName, []string{"Customer:111", "Customer:123"})

		enabled := featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != true {
			t.Errorf("Expected flag to be true but got %v", enabled)
		}

		vexiFakeAdapter.RemoveFeatureFlag(featureName)

		enabled = featuresAPI.IsEnabledWithDefaultValue(ctx, featureName, false, vexi.NewActor("Customer:123"))
		if enabled != false {
			t.Errorf("Expected flag to be true but got %v", enabled)
		}
	})
}

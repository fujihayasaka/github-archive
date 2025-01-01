package featureflags

import (
	"context"
	"os/exec"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewVexiClient_FFLite_ShouldHaveValuesFromLocalYaml(t *testing.T) {
	// This test validates that, when running locally, the flags from
	// config/kustomize/devoverlays/feature-flags.yml are loaded into the
	// and the feature flag lite server is setup correctly to respond by script/setup
	// (via script/fm-lite-bootstrap)

	ctx := context.Background()
	cfg := &Config{VexiFFLiteUrl: "http://localhost:8090"} // must define a way to indicate dev mode
	client, err := newVexiClient(ctx, cfg, "dotcom")
	require.NoError(t, err, "expected dev-mode client creation to succeed")

	// Valiate that the ims_vexi_feature_flag_canary is set to true
	// meaning we've correctly connected to fm lite
	require.True(t, client.logIfVexiDataCorrect(context.Background()), "dev mode should have correct feature flag data")
}

func TestNewVexiClient_FFLite_WithFullyEnabledFlag(t *testing.T) {
	const flagName = "fully-enabled-flag"
	actorName := getFakeUserActor()

	ctx := context.Background()
	cfg := &Config{VexiFFLiteUrl: "http://localhost:8090"} // must define a way to indicate dev mode
	client, err := newVexiClient(ctx, cfg, "dotcom")
	require.NoError(t, err, "expected dev-mode client creation to succeed")

	cmd := exec.Command("bash", "-c", "fm feature enable --create --feature-names "+flagName)
	err = cmd.Run()
	require.NoError(t, err, "expected no error when running fm command")

	require.True(t, client.IsFeatureFlagEnabledGlobally(ctx, flagName), "flag should to be enabled")
	require.True(t, client.IsFeatureFlagEnabledForActor(ctx, flagName, actorName), "flag should be enabled for actor as enabled globally")
}

func TestNewVexiClient_FFLite_WithFlagForActor(t *testing.T) {
	const (
		flagName = "actor-enabled-flag"
	)

	actorName := getFakeUserActor()

	ctx := context.Background()
	cfg := &Config{VexiFFLiteUrl: "http://localhost:8090"} // must define a way to indicate dev mode
	client, err := newVexiClient(ctx, cfg, "dotcom")
	require.NoError(t, err, "expected dev-mode client creation to succeed")

	//nolint:gosec // This is just a test
	cmd := exec.Command("bash", "-c",
		"fm feature create --feature-names "+flagName+
			" && fm feature actor add --feature-names "+flagName+
			" --actor-ids "+actorName.VexiID())
	err = cmd.Run()
	require.NoError(t, err, "expected no error when running fm command")

	require.False(t, client.IsFeatureFlagEnabledGlobally(ctx, flagName), "flag shouldn't be globally enabled")
	require.True(t, client.IsFeatureFlagEnabledForActor(ctx, flagName, actorName), "flag should be enabled for actor")
}

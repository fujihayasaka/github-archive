package models

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestListPolicyEnabledModels(t *testing.T) {
	t.Run("filters out policy-disabled models", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		disabledState := capi.ModelPolicyStateDisabled
		enabledState := capi.ModelPolicyStateEnabled
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "model-1", Name: "Model 1", Policy: &capi.ModelPolicy{State: enabledState}},
				{ID: "model-2", Name: "Model 2", Policy: &capi.ModelPolicy{State: disabledState}},
				{ID: "model-3", Name: "Model 3", Policy: nil},
			}, nil
		}

		ffs := featureflags.NewNoopClient(allModelPickerFlags())
		svc := NewService(capiClient, ffs)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 3) // AutoModel + model-1 + model-3

		// Verify AutoModel is first
		assert.Equal(t, capi.AutoMode, models[0].ID)

		// Verify policy-enabled model is included
		assert.Equal(t, "model-1", models[1].ID)

		// Verify policy-nil model is included
		assert.Equal(t, "model-3", models[2].ID)

		// Verify policy-disabled model is NOT included
		for _, model := range models {
			assert.NotEqual(t, "model-2", model.ID)
		}
	})

	t.Run("includes models with Policy.State = ModelPolicyStateEnabled", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		enabledState := capi.ModelPolicyStateEnabled
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "enabled-model", Name: "Enabled Model", Policy: &capi.ModelPolicy{State: enabledState}},
			}, nil
		}

		ffs := featureflags.NewNoopClient(allModelPickerFlags())
		svc := NewService(capiClient, ffs)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 2) // AutoModel + enabled-model

		// Verify AutoModel is first
		assert.Equal(t, capi.AutoMode, models[0].ID)

		// Verify enabled model is included
		assert.Equal(t, "enabled-model", models[1].ID)
	})

	t.Run("includes models with Policy.State = ModelPolicyStateUnconfigured", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		unconfiguredState := capi.ModelPolicyStateUnconfigured
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "unconfigured-model", Name: "Unconfigured Model", Policy: &capi.ModelPolicy{State: unconfiguredState}},
			}, nil
		}

		ffs := featureflags.NewNoopClient(allModelPickerFlags())
		svc := NewService(capiClient, ffs)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 2) // AutoModel + unconfigured-model

		// Verify AutoModel is first
		assert.Equal(t, capi.AutoMode, models[0].ID)

		// Verify unconfigured model is included
		assert.Equal(t, "unconfigured-model", models[1].ID)
	})

	t.Run("includes models with Policy = nil", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "nil-policy-model", Name: "Nil Policy Model", Policy: nil},
			}, nil
		}

		ffs := featureflags.NewNoopClient(allModelPickerFlags())
		svc := NewService(capiClient, ffs)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 2) // AutoModel + nil-policy-model

		// Verify AutoModel is first
		assert.Equal(t, capi.AutoMode, models[0].ID)

		// Verify nil-policy model is included
		assert.Equal(t, "nil-policy-model", models[1].ID)
	})

	t.Run("AutoModel is prepended after filtering", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		disabledState := capi.ModelPolicyStateDisabled
		enabledState := capi.ModelPolicyStateEnabled
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "model-1", Name: "Model 1", Policy: &capi.ModelPolicy{State: enabledState}},
				{ID: "model-2", Name: "Model 2", Policy: &capi.ModelPolicy{State: disabledState}},
				{ID: "model-3", Name: "Model 3", Policy: &capi.ModelPolicy{State: disabledState}},
				{ID: "model-4", Name: "Model 4", Policy: &capi.ModelPolicy{State: enabledState}},
			}, nil
		}

		ffs := featureflags.NewNoopClient(allModelPickerFlags())
		svc := NewService(capiClient, ffs)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 3) // AutoModel + model-1 + model-4

		// Verify AutoModel is first
		assert.Equal(t, capi.AutoMode, models[0].ID)
		assert.Equal(t, "Auto", models[0].Name)

		// Verify only enabled models follow AutoModel
		assert.Equal(t, "model-1", models[1].ID)
		assert.Equal(t, "model-4", models[2].ID)
	})

	t.Run("returns only AutoModel when all models are disabled", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		disabledState := capi.ModelPolicyStateDisabled
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "model-1", Name: "Model 1", Policy: &capi.ModelPolicy{State: disabledState}},
				{ID: "model-2", Name: "Model 2", Policy: &capi.ModelPolicy{State: disabledState}},
			}, nil
		}

		ffs := featureflags.NewNoopClient(allModelPickerFlags())
		svc := NewService(capiClient, ffs)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 1) // Only AutoModel

		// Verify only AutoModel is returned
		assert.Equal(t, capi.AutoMode, models[0].ID)
		assert.Equal(t, "Auto", models[0].Name)
	})

	t.Run("returns only AutoModel when CAPI returns empty list", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{}, nil
		}

		ffs := featureflags.NewNoopClient(allModelPickerFlags())
		svc := NewService(capiClient, ffs)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 1) // Only AutoModel

		// Verify only AutoModel is returned
		assert.Equal(t, capi.AutoMode, models[0].ID)
		assert.Equal(t, "Auto", models[0].Name)
	})

	t.Run("filters out models when feature flag is disabled", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{
				{ID: capi.ClaudeSonnet45, Name: "Claude Sonnet 4.5", Policy: nil},
				{ID: capi.GPT52Codex, Name: "GPT 5.2 Codex", Policy: nil},
			}, nil
		}

		// Disable the feature flag for ClaudeSonnet45, but enable GPT52Codex
		flags := allModelPickerFlags()
		flags[featureflags.CodingAgentModelPickerClaudeSonnet45] = false
		ffs := featureflags.NewNoopClient(flags)
		svc := NewService(capiClient, ffs)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 2) // AutoModel + GPT52Codex (ClaudeSonnet45 filtered out)

		// Verify AutoModel is first
		assert.Equal(t, capi.AutoMode, models[0].ID)

		// Verify GPT52Codex is included
		assert.Equal(t, capi.GPT52Codex, models[1].ID)

		// Verify ClaudeSonnet45 is NOT included
		for _, model := range models {
			assert.NotEqual(t, capi.ClaudeSonnet45, model.ID)
		}
	})

	t.Run("includes models when feature flag is enabled", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{
				{ID: capi.ClaudeSonnet45, Name: "Claude Sonnet 4.5", Policy: nil},
			}, nil
		}

		// Enable the feature flag for ClaudeSonnet45
		flags := allModelPickerFlags()
		flags[featureflags.CodingAgentModelPickerClaudeSonnet45] = true
		ffs := featureflags.NewNoopClient(flags)
		svc := NewService(capiClient, ffs)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 2) // AutoModel + ClaudeSonnet45

		// Verify AutoModel is first
		assert.Equal(t, capi.AutoMode, models[0].ID)

		// Verify ClaudeSonnet45 is included
		assert.Equal(t, capi.ClaudeSonnet45, models[1].ID)
	})
}

// allModelPickerFlags returns a map with all model picker feature flags enabled.
func allModelPickerFlags() map[string]bool {
	flags := make(map[string]bool)
	for _, flag := range capi.CodingAgentModelPickerModelFlags {
		flags[flag] = true
	}
	return flags
}

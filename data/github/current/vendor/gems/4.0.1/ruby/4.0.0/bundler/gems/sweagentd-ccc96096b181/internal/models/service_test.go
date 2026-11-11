package models

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/capi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestListPolicyEnabledModels(t *testing.T) {
	t.Run("filters out policy-disabled models", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		disabledState := capi.ModelPolicyStateDisabled
		enabledState := capi.ModelPolicyStateEnabled
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "model-1", Name: "Model 1", Policy: &capi.ModelPolicy{State: enabledState}},
				{ID: "model-2", Name: "Model 2", Policy: &capi.ModelPolicy{State: disabledState}},
				{ID: "model-3", Name: "Model 3", Policy: nil},
			}, nil
		}

		svc := NewService(capiClient)
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
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "enabled-model", Name: "Enabled Model", Policy: &capi.ModelPolicy{State: enabledState}},
			}, nil
		}

		svc := NewService(capiClient)
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
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "unconfigured-model", Name: "Unconfigured Model", Policy: &capi.ModelPolicy{State: unconfiguredState}},
			}, nil
		}

		svc := NewService(capiClient)
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
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "nil-policy-model", Name: "Nil Policy Model", Policy: nil},
			}, nil
		}

		svc := NewService(capiClient)
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
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "model-1", Name: "Model 1", Policy: &capi.ModelPolicy{State: enabledState}},
				{ID: "model-2", Name: "Model 2", Policy: &capi.ModelPolicy{State: disabledState}},
				{ID: "model-3", Name: "Model 3", Policy: &capi.ModelPolicy{State: disabledState}},
				{ID: "model-4", Name: "Model 4", Policy: &capi.ModelPolicy{State: enabledState}},
			}, nil
		}

		svc := NewService(capiClient)
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
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{ID: "model-1", Name: "Model 1", Policy: &capi.ModelPolicy{State: disabledState}},
				{ID: "model-2", Name: "Model 2", Policy: &capi.ModelPolicy{State: disabledState}},
			}, nil
		}

		svc := NewService(capiClient)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 1) // Only AutoModel

		// Verify only AutoModel is returned
		assert.Equal(t, capi.AutoMode, models[0].ID)
		assert.Equal(t, "Auto", models[0].Name)
	})

	t.Run("returns only AutoModel when CAPI returns empty list", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{}, nil
		}

		svc := NewService(capiClient)
		models, err := svc.ListPolicyEnabledModels(context.Background(), 123)

		require.NoError(t, err)
		require.Len(t, models, 1) // Only AutoModel

		// Verify only AutoModel is returned
		assert.Equal(t, capi.AutoMode, models[0].ID)
		assert.Equal(t, "Auto", models[0].Name)
	})
}

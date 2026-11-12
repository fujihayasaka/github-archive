package core_test

import (
	"context"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUserScopedMemoryFlagForIntegration(t *testing.T) {
	tests := []struct {
		name          string
		integrationID string
		wantFlag      string
	}{
		// CCR — requires additional flag
		{name: "copilot-pr-reviews", integrationID: "copilot-pr-reviews", wantFlag: core.FeatureUserScopedMemoryCCR},
		{name: "copilot-pr-reviews-dev", integrationID: "copilot-pr-reviews-dev", wantFlag: core.FeatureUserScopedMemoryCCR},
		// Other integrations — no additional flag required
		{name: "copilot-developer", integrationID: "copilot-developer", wantFlag: ""},
		{name: "vscode-chat", integrationID: "vscode-chat", wantFlag: ""},
		{name: "copilot-developer-cli", integrationID: "copilot-developer-cli", wantFlag: ""},
		{name: "unknown integration", integrationID: "some-unknown-client", wantFlag: ""},
		{name: "empty integration", integrationID: "", wantFlag: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := core.UserScopedMemoryFlagForIntegration(tt.integrationID)
			assert.Equal(t, tt.wantFlag, got)
		})
	}
}

func TestUserScopedMemoryFlagFromContext(t *testing.T) {
	t.Run("CCR integration in context returns CCR flag", func(t *testing.T) {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), "copilot-pr-reviews")
		assert.Equal(t, core.FeatureUserScopedMemoryCCR, core.UserScopedMemoryFlagFromContext(ctx))
	})

	t.Run("non-CCR integration in context returns empty", func(t *testing.T) {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), "copilot-developer")
		assert.Equal(t, "", core.UserScopedMemoryFlagFromContext(ctx))
	})

	t.Run("no integration in context returns empty", func(t *testing.T) {
		ctx := context.Background()
		assert.Equal(t, "", core.UserScopedMemoryFlagFromContext(ctx))
	})
}

func TestUserScopedMemoryFlag(t *testing.T) {
	const userID int64 = 42

	t.Run("CfI Pro user routes to CFI flag", func(t *testing.T) {
		ctx := requestctx.NewContext(t.Context())
		err := requestctx.AddCopilotUserDetails(ctx, userID, &copilotUsersTwirp.CopilotUserDetails{
			Id:            uint64(userID),
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			HasPaidAccess: true,
		})
		require.NoError(t, err)

		flag, err := core.UserScopedMemoryFlag(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, core.FeatureUserScopedMemoryCFI, flag)
	})

	t.Run("CfI Pro Plus user routes to CFI flag", func(t *testing.T) {
		ctx := requestctx.NewContext(t.Context())
		err := requestctx.AddCopilotUserDetails(ctx, userID, &copilotUsersTwirp.CopilotUserDetails{
			Id:            uint64(userID),
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
			HasPaidAccess: true,
		})
		require.NoError(t, err)

		flag, err := core.UserScopedMemoryFlag(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, core.FeatureUserScopedMemoryCFI, flag)
	})

	t.Run("CfB user routes to standard flag", func(t *testing.T) {
		ctx := requestctx.NewContext(t.Context())
		err := requestctx.AddCopilotUserDetails(ctx, userID, &copilotUsersTwirp.CopilotUserDetails{
			Id:            uint64(userID),
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			HasPaidAccess: true,
		})
		require.NoError(t, err)

		flag, err := core.UserScopedMemoryFlag(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, core.FeatureUserScopedMemory, flag)
	})

	t.Run("CfE user routes to standard flag", func(t *testing.T) {
		ctx := requestctx.NewContext(t.Context())
		err := requestctx.AddCopilotUserDetails(ctx, userID, &copilotUsersTwirp.CopilotUserDetails{
			Id:            uint64(userID),
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
			HasPaidAccess: true,
		})
		require.NoError(t, err)

		flag, err := core.UserScopedMemoryFlag(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, core.FeatureUserScopedMemory, flag)
	})

	t.Run("Education Free user routes to standard flag", func(t *testing.T) {
		ctx := requestctx.NewContext(t.Context())
		// Education Free: CopilotPlanFromUser returns CopilotForIndividual (IsPaidIndividual=true)
		// but HasPaidAccess is false, so they should NOT route to CFI.
		err := requestctx.AddCopilotUserDetails(ctx, userID, &copilotUsersTwirp.CopilotUserDetails{
			Id:            uint64(userID),
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			HasFreeAccess: true,
			HasPaidAccess: false,
		})
		require.NoError(t, err)

		flag, err := core.UserScopedMemoryFlag(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, core.FeatureUserScopedMemory, flag)
	})

	t.Run("no user details in context falls back to standard flag", func(t *testing.T) {
		ctx := requestctx.NewContext(t.Context())
		flag, err := core.UserScopedMemoryFlag(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, core.FeatureUserScopedMemory, flag)
	})

	t.Run("no requestctx in context falls back to standard flag", func(t *testing.T) {
		ctx := t.Context()
		flag, err := core.UserScopedMemoryFlag(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, core.FeatureUserScopedMemory, flag)
	})
}

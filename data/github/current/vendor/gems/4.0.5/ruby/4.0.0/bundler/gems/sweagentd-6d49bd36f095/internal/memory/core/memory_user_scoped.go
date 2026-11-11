package core

import (
	"context"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/requestctx"
)

// integrationToUserScopedMemoryFlag maps known CAPI integration IDs to their
// per-client user-scoped memory feature flag. Integrations not listed here
// do not require an additional flag beyond the general FeatureUserScopedMemory.
var integrationToUserScopedMemoryFlag = map[string]string{
	"copilot-pr-reviews":     FeatureUserScopedMemoryCCR,
	"copilot-pr-reviews-dev": FeatureUserScopedMemoryCCR,
}

// UserScopedMemoryFlagForIntegration returns the per-client user-scoped memory
// feature flag for the given integration ID. Returns an empty string when no
// additional flag is required for the integration.
func UserScopedMemoryFlagForIntegration(integrationID string) string {
	if flag, ok := integrationToUserScopedMemoryFlag[integrationID]; ok {
		return flag
	}
	return ""
}

// UserScopedMemoryFlagFromContext extracts the integration ID from ctx and
// resolves the per-client user-scoped memory feature flag.
func UserScopedMemoryFlagFromContext(ctx context.Context) string {
	return UserScopedMemoryFlagForIntegration(featureflags.IntegrationIDFromContext(ctx))
}

// UserScopedMemoryFlag returns the correct flag name for the user's plan.
// CfI Pro/Pro+ users are routed to FeatureUserScopedMemoryCFI; everyone else
// uses FeatureUserScopedMemory. The plan is read from the context cache.
// If user details are not in the cache, falls back to FeatureUserScopedMemory.
// The HasPaidAccess check excludes Education Free users (who have IsPaidIndividual
// via CopilotPlanFromUser but aren't Pro+), matching dotcom's copilot_plan_at_least?(Pro).
func UserScopedMemoryFlag(ctx context.Context, userID int64) (string, error) {
	details, ok := requestctx.CopilotUserDetails(ctx, userID)
	if !ok || details == nil {
		return FeatureUserScopedMemory, nil
	}

	plan, err := githubtwirp.CopilotPlanFromUser(details)
	if err != nil {
		return FeatureUserScopedMemory, err
	}

	if plan.IsPaidIndividual() && details.HasPaidAccess {
		return FeatureUserScopedMemoryCFI, nil
	}

	return FeatureUserScopedMemory, nil
}

package githubtwirp

import (
	"context"
	"errors"
	"fmt"
	"strings"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

const (
	PREMIUM_REQUESTS = copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS
	CHAT_REQUESTS    = copilotLimitersTwirp.QuotaType_QUOTA_TYPE_CHAT
)

var ErrCustomerSelectionRequired = errors.New("customer selection required")

// QuotaRemainingResponse contains the quota information for a user.
type QuotaRemainingResponse struct {
	Remaining        int32
	Total            int32
	OveragePermitted bool
	Unlimited        bool
}

// IsMultiSKU checks if the given SKU is a multi SKU.
func IsMultiSKU(accessType string) bool {
	return strings.Contains(strings.ToLower(accessType), "multi")
}

func CanProceedWithUsage(ctx context.Context, twirpClient ClientInterface, customerID, userID, orgID, repoID int64) (bool, error) {
	entityDetail := &billingProto.EntityDetail{
		CustomerId: fmt.Sprintf("%d", customerID),
	}
	if orgID > 0 {
		entityDetail.OwnerId = orgID
	}
	if userID > 0 {
		entityDetail.ActorId = userID
	}
	if repoID > 0 {
		entityDetail.RepoId = repoID
	}

	response, err := twirpClient.BillingClient().CanProceedWithUsage(ctx, &billingProto.CanProceedWithUsageRequest{
		UsageKey: &billingProto.UsageKey{
			Sku:          "coding_agent_premium_request",
			Product:      "copilot",
			Quantity:     1,
			EntityDetail: entityDetail,
		},
	})
	if err != nil {
		return false, fmt.Errorf("failed to check if can proceed with usage: %w", err)
	}

	return response.CanProceed, nil
}

// GetQuotaRemaining returns the remaining and total quota for the requested quota type.
// If userDetails is nil, this method will fetch them to preserve existing call sites.
func GetQuotaRemaining(ctx context.Context, twirpClient ClientInterface, userID int64, quotaType copilotLimitersTwirp.QuotaType, userDetails *copilotUsersTwirp.CopilotUserDetails) (*QuotaRemainingResponse, error) {
	if userDetails == nil {
		fetchedUserDetails, fetchErr := twirpClient.GetCopilotUserDetails(ctx, userID)
		if fetchErr != nil {
			return nil, fmt.Errorf("failed to get user details: %w", fetchErr)
		}
		userDetails = fetchedUserDetails
	}

	quotaRemaining, err := twirpClient.LimiterAPI().GetQuotaRemaining(ctx, &copilotLimitersTwirp.GetQuotaRemainingRequest{
		CopilotTrackingId: userDetails.GetAnalyticsTrackingId(),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get quota remaining: %w", err)
	}

	if quotaRemaining.GetQuotaDetails() == nil {
		return nil, fmt.Errorf("quota details are nil for user %d", userID)
	}

	for _, quota := range quotaRemaining.QuotaDetails {
		if quota.GetQuotaType() == quotaType {
			return &QuotaRemainingResponse{
				Remaining:        quota.GetRemaining(),
				Total:            quota.GetEntitlement(),
				OveragePermitted: quota.GetOveragePermitted(),
				Unlimited:        quota.GetUnlimited(),
			}, nil
		}
	}

	return nil, fmt.Errorf("quota type %v not found for user %d", quotaType, userID)
}

// CheckPremiumQuota checks if a user has sufficient premium quota to proceed with an action.
// It returns (hasSufficientQuota bool, totalQuota int32, error) where totalQuota is the user's total quota entitlement.
// When the billing platform feature flag is enabled, it also checks if the user can proceed with usage
// via the billing platform. Returns an error if quota checks fail unexpectedly (not if quota is exhausted).
func CheckPremiumQuota(ctx context.Context, twirpClient ClientInterface, ffClient featureflags.Client, obsv observability.Exporters, ownerID int64, repoID int64, userID int64) (bool, int32, error) {
	userDetails, err := twirpClient.GetCopilotUserDetails(ctx, userID)
	if err != nil {
		return false, 0, fmt.Errorf("failed to get user details: %w", err)
	}
	if userDetails == nil {
		return false, 0, fmt.Errorf("user details are nil for user %d", userID)
	}

	plan, err := CopilotPlanFromUser(userDetails)
	if err != nil {
		return false, 0, fmt.Errorf("failed to resolve copilot plan: %w", err)
	}

	quotaType := PREMIUM_REQUESTS
	quotaTypeLabel := "premium_interactions"
	disableBillingGate := plan == CopilotForIndividualFree && ffClient.IsEnabledForUser(ctx, featureflags.CodingAgentFreeUsersExperiment, userID)
	// Temporary experiment: for free plan users in the copilot_coding_agent_free_users_exp treatment group,
	// we gate coding agent access on chat quota rather than premium interactions.
	if plan == CopilotForIndividualFree {
		if !disableBillingGate {
			obsv.LoggerWithTelemetry(ctx).Info("free plan user without experiment flag; denying coding agent access")
			return false, 0, nil
		}
		quotaType = CHAT_REQUESTS
		quotaTypeLabel = "chat"
	}

	quotaResp, err := GetQuotaRemaining(ctx, twirpClient, userID, quotaType, userDetails)
	if err != nil {
		return false, 0, fmt.Errorf("failed to check quota remaining: %w", err)
	}
	obsv.LoggerWithTelemetry(ctx).Info(fmt.Sprintf("%s quota status: remaining=%d, total=%d, overagePermitted=%t, unlimited=%t", quotaTypeLabel, quotaResp.Remaining, quotaResp.Total, quotaResp.OveragePermitted, quotaResp.Unlimited))

	customerID, err := twirpClient.GetCustomerID(ctx, userID)
	if err != nil {
		return false, 0, fmt.Errorf("failed to get the customer id: %w", err)
	}
	if customerID == -1 {
		// In this case the customer has multiple customers available and has not selected one yet. Return a session error so that they can be prompted to select one.
		obsv.LoggerWithTelemetry(ctx).Info("user has multiple customers but has not selected one")
		obsv.Increment(ctx, "events.customer_not_selected", stats.Tags{})
		return false, quotaResp.Remaining, ErrCustomerSelectionRequired
	}

	if !disableBillingGate {
		// Users with unlimited quota can always proceed
		if quotaResp.Unlimited {
			obsv.LoggerWithTelemetry(ctx).Info("user has unlimited quota, allowing access")
			return true, quotaResp.Total, nil
		}

		canProceedWithUsage, err := CanProceedWithUsage(ctx, twirpClient, customerID, userID, ownerID, repoID)
		if err != nil {
			// Log the error but fail open
			obsv.LoggerWithTelemetry(ctx).Error(fmt.Sprintf("failed to call Can Proceed With Usage. This should fail open, returning true: %v", err))
			return true, quotaResp.Total, nil
		}

		if quotaResp.Remaining > 0 || canProceedWithUsage {
			obsv.LoggerWithTelemetry(ctx).Info("user has sufficient premium quota after checking billing platform")
			return true, quotaResp.Total, nil
		}

		obsv.LoggerWithTelemetry(ctx).Info("user has no remaining premium quota and overage is not permitted")
		obsv.Increment(ctx, "events.premium_quota_exceeded", stats.Tags{})
		return false, quotaResp.Total, nil
	}

	// Free users in experiment rely on limiter and skip the CanProceedWithUsage billing gate while the experiment is running.
	if quotaResp.Remaining > 0 || quotaResp.OveragePermitted {
		obsv.LoggerWithTelemetry(ctx).Info("user has sufficient quota after limiter check")
		return true, quotaResp.Total, nil
	}

	obsv.LoggerWithTelemetry(ctx).Info("user has no remaining quota and overage is not permitted")
	obsv.Increment(ctx, "events.premium_quota_exceeded", stats.Tags{})
	return false, quotaResp.Total, nil
}

// ResolveDisplayLogin resolves the expected value of DisplayLogin by using
// the user ID to fetch a display login using the GitHub Sweagentd Twirp service.
// For more information about why display_login is critical in Proxima, see:
// https://github.com/github/proxima/blob/9bb65232b59a2a5f623106c082686c3fcd644c88/docs/tenancy/namespacing.md
//
// This method is written in such a way that it should *never* error outside of a Proxima environment.
// The behavior of this method outside of a Proxima environment is only to set DisplayLogin to Login.
// There shouldn't be any additional service call / twirp interaction in normal production.
func ResolveDisplayLogin(ctx context.Context, twirpClient ClientInterface, obsv observability.Exporters, ffClient featureflags.Client, userID uint64, originalLogin string) (resolvedDisplayLogin string, err error) {
	displayLogin := originalLogin

	// We check for presence of tenant to infer we are in a proxima context. This is implicitly required because the twirp call will need
	// a tenant header to resolve correctly. This is a cheap way to make sure this only runs on proxima without an dependency piped around.
	tenant := requestctx.TenantSlug(ctx)
	if tenant != "" {
		result, err := twirpClient.SweagentdAPI().ResolveUserIDToDisplayLogin(ctx, &sweagentdTwirp.ResolveUserIDToDisplayLoginRequest{
			UserId: userID,
		})

		if err != nil {
			return "", fmt.Errorf("failed to resolve user ID to display login")
		}

		if result.GetDisplayLogin() == "" {
			return "", fmt.Errorf("failed to resolve user ID to display login, empty display login returned")
		}

		displayLogin = result.GetDisplayLogin()
	}

	return displayLogin, nil
}

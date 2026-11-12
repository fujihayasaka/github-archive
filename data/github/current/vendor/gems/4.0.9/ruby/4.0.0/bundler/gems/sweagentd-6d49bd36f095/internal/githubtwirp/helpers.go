package githubtwirp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

const (
	PREMIUM_INTERACTION_REQUESTS = copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS

	// Duration for caching quota remaining responses is 5 minutes
	quotaRemainingCacheTTL = 5 * time.Minute
	quotaRemainingPrefix   = "githubtwirp:quota_remaining:user"

	// medianAIUsPerJob is the median AIUs consumed per job when token-based billing is enabled.
	// This is used as a threshold to determine if a user has enough quota to run a job.
	// The value is from below query
	// https://dataexplorer.azure.com/clusters/gh-analytics.eastus/databases/hydro?query=H4sIAAAAAAAAA3VRTW%2FbMAy951cQucQeElfJ2l2KXQbk0EsxNN1pGARaZhEtluRKdAsP%2B%2FGj8tHa2MaLpIf3qPfIlhgSY%2BRH6wg%2BQ4NMLNdiozafVmqzWt%2BUt7NWWOSbf3M%2BrtT6zEmHPmXC4NFZU3yff%2Fm2u7vf7nbzJcy394%2Fbh68Pd7vt%2FMeZj7bXXbQmd1WVWp%2FQLk7Q6xP6M9TaEQueTh6wxkTFYj80MSzKSt6tPE3obBtYvyj93AdGTS%2FkeVHOQOo3vO4pEhzw6YA6Z5DsroOa%2BJXIQ%2FE%2Biqq6JJ5KL%2F3RGEpJ89AR7DFp9IPIJf%2BUbpMPTK7jobCeKaJhG7y2TQlXV%2FAUIoi%2FOOR0Z13qncNofxEcgVw5eh6KCYkluzAKFxpqtetbtl1rKZbw4X1uy4mS63qszDN%2F7tGz5UF79EGcwFpdqlLS6W0vb43qAab%2Bb2ejhcz%2Bsu2oseiPrjuKWrjyvdyMLMPKnsaRlnCjyuVYli3%2FV3bJM5Jl2ITe54zHsyj%2FAHhxkjXZAgAA
	medianAIUsPerJob int32 = 7
)

var ErrCustomerSelectionRequired = errors.New("customer selection required")

// QuotaRemainingResponse contains the quota information for a user.
type QuotaRemainingResponse struct {
	Remaining           int32
	PercentRemaining    float64
	Total               int32
	OveragePermitted    bool
	Unlimited           bool
	TokenBasedBilling   bool
	CanProceedWithUsage *bool
}

// QuotaSnapshot contains quota snapshot fields used by callers that need a
// user-facing view of quota state.
type QuotaSnapshot struct {
	Remaining           int32
	PercentageRemaining float64
	CanStartSession     bool
	Unlimited           bool
	CopilotPlan         string
}

// IsMultiSKU checks if the given SKU is a multi SKU.
func IsMultiSKU(accessType string) bool {
	return strings.Contains(strings.ToLower(accessType), "multi")
}

// hasEnoughQuota compares the remaining quota with the median usage per job.
// If TokenBasedBilling is enabled for this user, the unit is in AIUs; otherwise, it is in PRUs.
// for AIU, the median AIU per job is captured in medianAIUsPerJob.
// The current PRU check is remaining > 0. The median PRU per job is ~2, so we could check against 2 if needed
func hasEnoughQuota(isTokenBasedBilling bool, remaining int32) bool {
	if isTokenBasedBilling {
		return remaining >= medianAIUsPerJob
	}
	return remaining > 0
}

// CanProceedWithUsage checks with the billing platform if the user can proceed with usage based on their customer and entity details.
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

// GetQuotaRemaining returns the remaining and total quota for the premium interactions quota type.
// If preferReadCache is true, it checks cache first and falls back to limiter on cache miss.
// If userDetails is nil and a limiter call is needed, this method fetches user details.
func GetQuotaRemaining(ctx context.Context, twirpClient ClientInterface, userID int64, userDetails *copilotUsersTwirp.CopilotUserDetails, preferReadCache bool) (*QuotaRemainingResponse, bool, error) {
	integrationID := optionalStringPointer(twirpClient.CopilotIntegrationID())
	cacheKey := quotaRemainingCacheKey(ctx, userID, integrationID)

	if preferReadCache {
		if store := twirpClient.CacheStore(); store != nil {
			if cachedValue, ok := store.Get(cacheKey); ok && cachedValue != "" {
				var cachedQuota QuotaRemainingResponse
				if err := json.Unmarshal([]byte(cachedValue), &cachedQuota); err == nil {
					return &cachedQuota, true, nil
				}
			}
		}
	}

	if userDetails == nil {
		fetchedUserDetails, fetchErr := twirpClient.GetCopilotUserDetails(ctx, userID)
		if fetchErr != nil {
			return nil, false, fmt.Errorf("failed to get user details: %w", fetchErr)
		}
		userDetails = fetchedUserDetails
	}

	quotaRemaining, err := twirpClient.LimiterAPI().GetQuotaRemaining(ctx, &copilotLimitersTwirp.GetQuotaRemainingRequest{
		CopilotTrackingId: userDetails.GetAnalyticsTrackingId(),
		IntegrationId:     integrationID,
		InteractionId:     getInteractionID(ctx),
	})
	if err != nil {
		return nil, false, fmt.Errorf("failed to get quota remaining: %w", err)
	}

	if quotaRemaining.GetQuotaDetails() == nil {
		return nil, false, fmt.Errorf("quota details are nil for user %d", userID)
	}

	tokenBasedBilling := quotaRemaining.GetTokenBasedBilling()

	for _, quota := range quotaRemaining.QuotaDetails {
		if quota.GetQuotaType() == PREMIUM_INTERACTION_REQUESTS {
			return &QuotaRemainingResponse{
				Remaining:         quota.GetRemaining(),
				PercentRemaining:  quota.GetPercentRemaining(),
				Total:             quota.GetEntitlement(),
				OveragePermitted:  quota.GetOveragePermitted(),
				Unlimited:         quota.GetUnlimited(),
				TokenBasedBilling: tokenBasedBilling,
			}, false, nil
		}
	}

	return nil, false, fmt.Errorf("quota type %v not found for user %d", PREMIUM_INTERACTION_REQUESTS, userID)
}

func quotaRemainingCacheKey(ctx context.Context, userID int64, integrationID *string) string {
	normalizedIntegrationID := "none"
	if integrationID != nil {
		normalizedIntegrationID = *integrationID
	}

	tenantID := requestctx.TenantID(ctx)
	if tenantID == "" {
		tenantID = "no-tenant"
	}

	return fmt.Sprintf("%s%s:%d:%s", quotaRemainingPrefix, tenantID, userID, normalizedIntegrationID)
}

func setCachedQuotaRemaining(store cache.Store, key string, quota QuotaRemainingResponse) {
	if store == nil {
		return
	}

	marshaled, err := json.Marshal(quota)
	if err != nil {
		return
	}

	store.Set(key, string(marshaled), quotaRemainingCacheTTL)
}

func optionalStringPointer(values ...*string) *string {
	if len(values) == 0 || values[0] == nil || strings.TrimSpace(*values[0]) == "" {
		return nil
	}

	return values[0]
}

func getInteractionID(ctx context.Context) *string {
	requestID := requestid.GetGitHubRequestID(ctx)
	if requestID == "" {
		return nil
	}

	return &requestID
}

// CheckPremiumQuota checks if a user has sufficient premium quota to proceed with an action.
// It returns (hasSufficientQuota bool, totalQuota int32, tokenBasedBilling bool, error) where totalQuota is the user's total quota entitlement.
// When the billing platform feature flag is enabled, it also checks if the user can proceed with usage
// via the billing platform. Returns an error if quota checks fail unexpectedly (not if quota is exhausted).
// When preferCachedQuota is true, quota lookup checks cache first and falls back to limiter.
func CheckPremiumQuota(ctx context.Context, twirpClient ClientInterface, ffClient featureflags.Client, obsv observability.Exporters, ownerID, repoID, userID int64, preferCachedQuota bool) (bool, int32, bool, error) {
	userDetails, err := twirpClient.GetCopilotUserDetails(ctx, userID)
	if err != nil {
		return false, 0, false, fmt.Errorf("failed to get user details: %w", err)
	}
	if userDetails == nil {
		return false, 0, false, fmt.Errorf("user details are nil for user %d", userID)
	}

	integrationID := optionalStringPointer(twirpClient.CopilotIntegrationID())
	logger := obsv.LoggerWithTelemetry(ctx)
	cacheKey := quotaRemainingCacheKey(ctx, userID, integrationID)

	if integrationID == nil {
		logger.Debug("integration_id missing for limiter GetQuotaRemaining request")
	} else {
		logger.Debug("integration_id present for limiter GetQuotaRemaining request")
	}

	// If preferCachedQuota is true, read quota from cache first; on cache miss, call limiter GetQuotaRemaining.
	quotaResp, cacheHit, err := GetQuotaRemaining(ctx, twirpClient, userID, userDetails, preferCachedQuota)
	if err != nil {
		return false, 0, false, fmt.Errorf("failed to check quota remaining: %w", err)
	}

	// Check whether the user has enough remaining quota.
	hasEnoughRemaining := hasEnoughQuota(quotaResp.TokenBasedBilling, quotaResp.Remaining)
	obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("quota_type", PREMIUM_INTERACTION_REQUESTS.String()),
		kvp.Int32("remaining", quotaResp.Remaining),
		kvp.Int32("total", quotaResp.Total),
		kvp.Bool("overage_permitted", quotaResp.OveragePermitted),
		kvp.Bool("unlimited", quotaResp.Unlimited),
		kvp.Bool("token_based_billing", quotaResp.TokenBasedBilling),
		kvp.Bool("has_enough_quota", hasEnoughRemaining),
	).Info("Get Quota Remaining Response")

	customerID, err := twirpClient.GetCustomerID(ctx, userID)
	if err != nil {
		return false, 0, quotaResp.TokenBasedBilling, fmt.Errorf("failed to get the customer id: %w", err)
	}
	if customerID == -1 {
		// In this case the customer has multiple customers available and has not selected one yet. Return a session error so that they can be prompted to select one.
		obsv.LoggerWithTelemetry(ctx).Info("user has multiple customers but has not selected one")
		obsv.Increment(ctx, "events.customer_not_selected", stats.Tags{})
		return false, quotaResp.Remaining, quotaResp.TokenBasedBilling, ErrCustomerSelectionRequired
	}

	// Users with unlimited quota can always proceed
	if quotaResp.Unlimited {
		obsv.LoggerWithTelemetry(ctx).Info("user has unlimited quota, allowing access")
		return true, quotaResp.Total, quotaResp.TokenBasedBilling, nil
	}

	// If preferCachedQuota is true, read quota from cache first; on cache miss, call limiter CanProceedWithUsage
	var canProceedWithUsage bool
	if preferCachedQuota && quotaResp.CanProceedWithUsage != nil {
		canProceedWithUsage = *quotaResp.CanProceedWithUsage
	} else {
		canProceedWithUsage, err = CanProceedWithUsage(ctx, twirpClient, customerID, userID, ownerID, repoID)
		if err != nil {
			// Log the error but fail open
			obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to call Can Proceed With Usage. This should fail open, returning true")
			return true, quotaResp.Total, quotaResp.TokenBasedBilling, nil
		}

		// Cache canProceedWithUsage so it can be read from cache on subsequent calls when preferCachedQuota is enabled.
		quotaResp.CanProceedWithUsage = &canProceedWithUsage
	}

	if !cacheHit {
		setCachedQuotaRemaining(twirpClient.CacheStore(), cacheKey, *quotaResp)
	}

	if canProceedWithUsage != quotaResp.OveragePermitted {
		obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.Bool("can_proceed_with_usage", canProceedWithUsage),
			kvp.Bool("overage_permitted", quotaResp.OveragePermitted),
		).Info("canProceedWithUsage differs from quotaResp.OveragePermitted")
	} else {
		obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.Bool("can_proceed_with_usage", canProceedWithUsage),
			kvp.Bool("overage_permitted", quotaResp.OveragePermitted),
		).Info("canProceedWithUsage matches quotaResp.OveragePermitted")
	}

	if hasEnoughRemaining || canProceedWithUsage {
		obsv.LoggerWithTelemetry(ctx).Info("user has sufficient quota after checking billing platform")
		return true, quotaResp.Total, quotaResp.TokenBasedBilling, nil
	}

	obsv.LoggerWithTelemetry(ctx).Info("user has no remaining quota and overage is not permitted")
	obsv.Increment(ctx, "events.premium_quota_exceeded", stats.Tags{})
	return false, quotaResp.Total, quotaResp.TokenBasedBilling, nil
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

// ComposeQuotaSnapshot composes a quota snapshot for a user.
// This method is resilient to dependency failures and preserves the same
// fallback behavior used by quota snapshot handlers.
// Quota lookups always prefer cache first and fall back to live reads.
func ComposeQuotaSnapshot(ctx context.Context, twirpClient ClientInterface, ffClient featureflags.Client, obsv observability.Exporters, ownerID, repoID, userID int64) *QuotaSnapshot {
	logger := obsv.LoggerWithTelemetry(ctx)

	canStartSession := true
	cps, _, _, err := CheckPremiumQuota(ctx, twirpClient, ffClient, obsv, ownerID, repoID, userID, true)
	if err != nil {
		// Non-fatal: default to true so the user is not incorrectly blocked from starting a session.
		logger.WithContext(ctx).WithError(err).Warn("failed to check premium quota; defaulting can_start_session to true")
	} else {
		canStartSession = cps
	}

	remaining := int32(-1)
	percentageRemaining := -1.0
	unlimited := false
	quotaResp, _, err := GetQuotaRemaining(ctx, twirpClient, userID, nil, true)
	if err != nil {
		// Non-fatal: quota type not applicable for this user (e.g. free plan without the experiment).
		// Display fields default to -1 and unlimited=false; can_start_session remains accurate.
		logger.WithContext(ctx).WithError(err).Warn("failed to get quota remaining; display fields will be -1")
	} else {
		remaining = quotaResp.Remaining
		percentageRemaining = quotaResp.PercentRemaining
		unlimited = quotaResp.Unlimited
	}

	copilotPlan, err := GetCopilotPlan(ctx, twirpClient, userID)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Warn("failed to get copilot plan")
	}

	return &QuotaSnapshot{
		Remaining:           remaining,
		PercentageRemaining: percentageRemaining,
		CanStartSession:     canStartSession,
		Unlimited:           unlimited,
		CopilotPlan:         copilotPlan.String(),
	}
}

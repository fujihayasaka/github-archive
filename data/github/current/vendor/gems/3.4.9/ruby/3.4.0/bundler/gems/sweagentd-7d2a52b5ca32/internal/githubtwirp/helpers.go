package githubtwirp

import (
	"context"
	"errors"
	"fmt"
	"strings"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/feature-management-client-go/vexi/v2/extensions"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/google/uuid"
)

const (
	PREMIUM_REQUESTS = copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS
)

var ErrCustomerSelectionRequired = errors.New("customer selection required")

func IsCopilotSweEnabled(ctx context.Context, twirpClient ClientInterface, userID int64, repositoryID int64) (bool, error) {
	result, err := twirpClient.SweagentdAPI().ConfigurationForRepository(ctx, &sweagentdTwirp.ConfigurationForRepositoryRequest{
		RepositoryId: repositoryID,
		UserId:       uint64(userID),
	})
	if err != nil {
		return false, fmt.Errorf("failed to get monolith configuration for repository: %w", err)
	}

	return result.IsSweagentdEnabled, nil
}

// IsMultiSKU checks if the given SKU is a multi SKU.
func IsMultiSKU(accessType string) bool {
	return strings.Contains(strings.ToLower(accessType), "multi")
}

// GetCopilotUser gets the Copilot user details, and memoizes it in the context to not need to refetch it multiple times
func GetCopilotUserDetails(ctx context.Context, twirpClient ClientInterface, userID int64) (*copilotUsersTwirp.CopilotUserDetails, error) {
	// Check if we already have the user details in the context for this specific user ID
	if userDetails, ok := requestctx.CopilotUserDetails(ctx, userID); ok {
		return userDetails, nil
	}

	res, err := twirpClient.UserDetailAPI().GetCopilotUser(ctx, &copilotUsersTwirp.GetCopilotUserRequest{
		Id: uint64(userID),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get user details: %w", err)
	}

	// Memoize it in ctx for this specific user ID
	if err := requestctx.AddCopilotUserDetails(ctx, userID, res.UserDetails); err != nil {
		// Log the error but don't fail the request - memoization is just an optimization
		// We could add logging here if needed
	}

	return res.UserDetails, nil
}

func GetCustomerId(ctx context.Context, twirpClient ClientInterface, userID int64) (int64, error) {
	userDetails, err := GetCopilotUserDetails(ctx, twirpClient, userID)
	if err != nil {
		return 0, fmt.Errorf("failed to get user details: %w", err)
	}

	response, err := twirpClient.LimiterAPI().GetConsumptiveUser(ctx, &copilotLimitersTwirp.GetConsumptiveUserRequest{
		CopilotTrackingId: userDetails.GetAnalyticsTrackingId(),
	})
	if err != nil {
		return 0, fmt.Errorf("failed to get consumptive user: %w", err)
	}
	// Define as int64
	customerId := int64(0)

	if len(response.CustomerIds) == 0 && IsMultiSKU(response.AccessType.String()) {
		// this means that they have been assigned multiple seats
		// by non-associated (having different Customer records) entities
		// they must select their customer in their copilot settings
		// before they can use copilot

		// we will set the customer ID to -1 to indicate that they need to select a customer
		customerId = -1
	} else if len(response.CustomerIds) > 0 {
		customerId = response.CustomerIds[0]
	}

	return customerId, nil
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

func GetQuotaRemaining(ctx context.Context, twirpClient ClientInterface, userID int64, quotaType copilotLimitersTwirp.QuotaType) (remainingQuota int32, totalQuota int32, overagePermitted bool, err error) {
	userDetails, err := GetCopilotUserDetails(ctx, twirpClient, userID)
	if err != nil {
		return 0, 0, false, fmt.Errorf("failed to get user details: %w", err)
	}

	quotaRemaining, err := twirpClient.LimiterAPI().GetQuotaRemaining(ctx, &copilotLimitersTwirp.GetQuotaRemainingRequest{
		CopilotTrackingId: userDetails.GetAnalyticsTrackingId(),
	})
	if err != nil {
		return 0, 0, false, fmt.Errorf("failed to get quota remaining: %w", err)
	}

	if quotaRemaining.GetQuotaDetails() == nil {
		return 0, 0, false, fmt.Errorf("quota details are nil for user %d", userID)
	}

	for _, quota := range quotaRemaining.QuotaDetails {
		if quota.GetQuotaType() == quotaType {
			// Include unlimited flag as overage permitted to allow unlimited users access
			overage := quota.GetOveragePermitted() || quota.GetUnlimited()
			return quota.GetRemaining(), quota.GetEntitlement(), overage, nil
		}
	}

	return 0, 0, false, fmt.Errorf("quota type %v not found for user %d", quotaType, userID)
}

// CheckPremiumQuota checks if a user has sufficient premium quota to proceed with an action.
// It returns (hasSufficientQuota bool, totalQuota int32, error) where totalQuota is the user's total quota entitlement.
// When the billing platform feature flag is enabled, it also checks if the user can proceed with usage
// via the billing platform. Returns an error if quota checks fail unexpectedly (not if quota is exhausted).
func CheckPremiumQuota(ctx context.Context, twirpClient ClientInterface, ffClient featureflags.Client, obsv observability.Exporters, ownerID int64, repoID int64, userID int64) (bool, int32, error) {
	remainingQuota, totalQuota, overagePermitted, err := GetQuotaRemaining(ctx, twirpClient, userID, PREMIUM_REQUESTS)
	if err != nil {
		return false, 0, fmt.Errorf("failed to check quota remaining: %w", err)
	}
	obsv.LoggerWithTelemetry(ctx).Info(fmt.Sprintf("premium quota status: remaining=%d, total=%d, overagePermitted=%t", remainingQuota, totalQuota, overagePermitted))

	if ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentUseBillingPlatform, extensions.NewOrganization(fmt.Sprintf("%d", ownerID)), extensions.NewRepository(fmt.Sprintf("%d", repoID))) {
		obsv.LoggerWithTelemetry(ctx).Info("copilot_swe_agent_use_billing_platform feature flag is enabled - checking billing platform for CPWU quota")
		customerID, err := GetCustomerId(ctx, twirpClient, userID)
		if err != nil {
			return false, 0, fmt.Errorf("failed to get the customer id: %w", err)
		}
		if customerID == -1 {
			// In this case the customer has multiple customers available and has not selected one yet. Return a session error so that they can be prompted to select one.
			obsv.LoggerWithTelemetry(ctx).Info("user has multiple customers but has not selected one")
			obsv.Increment(ctx, "events.customer_not_selected", stats.Tags{})
			return false, remainingQuota, ErrCustomerSelectionRequired
		}

		canProceedWithUsage, err := CanProceedWithUsage(ctx, twirpClient, customerID, userID, ownerID, repoID)
		if err != nil {
			// Log the error but fail open
			obsv.LoggerWithTelemetry(ctx).Error(fmt.Sprintf("failed to call Can Proceed With Usage. This should fail open, returning true: %v", err))
			return true, totalQuota, nil
		}

		if remainingQuota > 0 || canProceedWithUsage {
			obsv.LoggerWithTelemetry(ctx).Info("user has sufficient premium quota after checking billing platform")
			return true, totalQuota, nil
		}
	} else {
		if remainingQuota > 0 || overagePermitted {
			obsv.LoggerWithTelemetry(ctx).Info("user has sufficient premium quota")
			return true, totalQuota, nil
		}
	}
	obsv.LoggerWithTelemetry(ctx).Info("user has no remaining premium quota and overage is not permitted")
	obsv.Increment(ctx, "events.premium_quota_exceeded", stats.Tags{})
	return false, totalQuota, nil
}

type HasAccessCheck struct {
	// An action that should be checked. These actions are defined in
	// https://github.com/github/github/blob/HEAD/config/access_control
	Action string
	// The ID resource to check access against. This is a dotcom model's numeric ID.
	ResourceId int64
	// The type of resource to check access against. This should map to a Rails model,
	// like Repository or Organization.
	ResourceType string
	// Optional: Specify an organization ID, for checks that require it.
	OrganizationID int64
	// Optional: Specify a repository ID, for checks that require it.
	RepositoryID int64
	// Optional: Specify a repository NWO (name with owner), for checks that require it.
	RepositoryNWO string
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

// This helper function takes in a user + token and a set of access checks to perform and returns true if they all pass
func TokenHasAccess(ctx context.Context, twirpClient ClientInterface, userInfo *requestctx.UserInfo, reqs []*HasAccessCheck) (bool, error) {
	// We want to guard against checking empty permissions so error in this case
	if len(reqs) == 0 {
		return false, fmt.Errorf("no access checks provided to verify")
	}

	logger := log.WithContext(ctx)

	reqObjs := make([]*coreTwirp.AuthorizationRequestObject, len(reqs))
	for i, req := range reqs {
		reqObjs[i] = &coreTwirp.AuthorizationRequestObject{
			Id:             fmt.Sprintf("%s-%s-%s", req.Action, req.ResourceType, uuid.NewString()),
			Action:         req.Action,
			ResourceId:     req.ResourceId,
			ResourceType:   req.ResourceType,
			OrganizationId: req.OrganizationID,
			RepositoryId:   req.RepositoryID,
			RepositoryNwo:  req.RepositoryNWO,
		}
	}
	batch := &coreTwirp.BatchControlAccessRequest{
		AccessToken:           userInfo.TokenInfo.Token,
		AuthorizationRequests: reqObjs,
		RequestIp:             userInfo.RequestIP,
	}

	api := twirpClient.AuthorizationAPI()
	result, err := api.BatchControlAccess(ctx, batch)
	if err != nil {
		return false, fmt.Errorf("failed to check access: %w", err)
	}
	// We want to know if all of the checks passed in where successful, so
	// iterate through each "decision" as to whether the check passed and
	// return false if any one of them failed, otherwise return true.
	var failedActions []string
	for i, decision := range result.Decisions {
		if !decision.GetDecision() {
			action := "unknown"
			if i < len(reqs) {
				action = reqs[i].Action
			}
			failedActions = append(failedActions, action)
		}
	}

	if len(failedActions) > 0 {
		logger.WithFields(
			kvp.String("failed_actions", strings.Join(failedActions, ",")),
			kvp.Int("total_checks", len(reqs)),
			kvp.Int("failed_checks", len(failedActions)),
		).Warn("token access check failed for specific actions")
		return false, nil
	}

	return true, nil
}

package githubtwirp

import (
	"context"
	"errors"
	"testing"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestGetQuotaRemaining_UsesProvidedUserDetails(t *testing.T) {
	ctx := context.Background()
	userID := int64(44)

	client := NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return nil, errors.New("unexpected user details fetch")
	}

	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id-3", req.GetCopilotTrackingId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
				{
					QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					Remaining:        5,
					Entitlement:      10,
					OveragePermitted: true,
					PercentRemaining: 0.5,
				},
			},
		}, nil
	}

	userDetails := &copilotUsersTwirp.CopilotUserDetails{
		Id:                  uint64(userID),
		AnalyticsTrackingId: "tracking-id-3",
	}

	quotaResp, err := GetQuotaRemaining(ctx, client, userID, PREMIUM_REQUESTS, userDetails)
	require.NoError(t, err)
	require.Equal(t, int32(5), quotaResp.Remaining)
	require.Equal(t, int32(10), quotaResp.Total)
	require.True(t, quotaResp.OveragePermitted)
	require.False(t, quotaResp.Unlimited)
}

func TestCheckPremiumQuota_FreePlanExperimentUsesChatQuota(t *testing.T) {
	ctx := context.Background()
	userID := int64(42)

	client := NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				Id:                  uint64(userID),
				AnalyticsTrackingId: "tracking-id",
				CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasFreeAccess:       true,
				HasLimitedAccess:    true,
			},
		}, nil
	}

	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id", req.GetCopilotTrackingId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
				{
					QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_CHAT,
					Remaining:   2,
					Entitlement: 7,
				},
				{
					QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					Remaining:   0,
					Entitlement: 0,
				},
			},
		}, nil
	}

	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CodingAgentFreeUsersExperiment: true,
	})

	hasQuota, totalQuota, err := CheckPremiumQuota(ctx, client, ffClient, observability.NewNoopExporters(), 1, 2, userID)
	require.NoError(t, err)
	require.True(t, hasQuota)
	require.Equal(t, int32(7), totalQuota)
}

func TestCheckPremiumQuota_FreePlanWithoutExperimentIsDenied(t *testing.T) {
	ctx := context.Background()
	userID := int64(43)

	client := NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				Id:                  uint64(userID),
				AnalyticsTrackingId: "tracking-id-2",
				CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasFreeAccess:       true,
				HasLimitedAccess:    true,
			},
		}, nil
	}

	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id-2", req.GetCopilotTrackingId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
				{
					QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_CHAT,
					Remaining:   0,
					Entitlement: 4,
				},
				{
					QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					Remaining:   0,
					Entitlement: 0,
				},
			},
		}, nil
	}

	ffClient := featureflags.NewNoopClient(map[string]bool{})

	hasQuota, totalQuota, err := CheckPremiumQuota(ctx, client, ffClient, observability.NewNoopExporters(), 1, 2, userID)
	require.NoError(t, err)
	require.False(t, hasQuota)
	require.Equal(t, int32(0), totalQuota)
}

func TestCheckPremiumQuota_PaidPlanUsesPremiumQuotaWithBillingGate(t *testing.T) {
	ctx := context.Background()
	userID := int64(45)

	client := NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				Id:                  uint64(userID),
				AnalyticsTrackingId: "tracking-id-4",
				CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasPaidAccess:       true,
			},
		}, nil
	}

	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id-4", req.GetCopilotTrackingId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
				{
					QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					Remaining:   0,
					Entitlement: 12,
				},
			},
		}, nil
	}

	client.NoopBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).
		Return(&billingProto.CanProceedWithUsageResponse{CanProceed: true}, nil)

	ffClient := featureflags.NewNoopClient(map[string]bool{})

	hasQuota, totalQuota, err := CheckPremiumQuota(ctx, client, ffClient, observability.NewNoopExporters(), 1, 2, userID)
	require.NoError(t, err)
	require.True(t, hasQuota)
	require.Equal(t, int32(12), totalQuota)
}

func TestCheckPremiumQuota_UnlimitedQuotaAllowsAccessEvenWhenCanProceedWithUsageIsFalse(t *testing.T) {
	ctx := context.Background()
	userID := int64(46)

	client := NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				Id:                  uint64(userID),
				AnalyticsTrackingId: "tracking-id-5",
				CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasPaidAccess:       true,
			},
		}, nil
	}

	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id-5", req.GetCopilotTrackingId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
				{
					QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					Remaining:   0,
					Entitlement: 0,
					Unlimited:   true,
				},
			},
		}, nil
	}

	client.NoopBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).
		Return(&billingProto.CanProceedWithUsageResponse{CanProceed: false}, nil)

	ffClient := featureflags.NewNoopClient(map[string]bool{})

	hasQuota, totalQuota, err := CheckPremiumQuota(ctx, client, ffClient, observability.NewNoopExporters(), 1, 2, userID)
	require.NoError(t, err)
	require.True(t, hasQuota, "user with unlimited quota should be allowed to proceed even when CanProceedWithUsage returns false")
	require.Equal(t, int32(0), totalQuota)
}

func TestGetQuotaRemaining_UnlimitedFlagIsReturnedSeparately(t *testing.T) {
	ctx := context.Background()
	userID := int64(48)

	client := NewNoopClient()
	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id-7", req.GetCopilotTrackingId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
				{
					QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					Remaining:        0,
					Entitlement:      0,
					OveragePermitted: false,
					Unlimited:        true,
				},
			},
		}, nil
	}

	userDetails := &copilotUsersTwirp.CopilotUserDetails{
		Id:                  uint64(userID),
		AnalyticsTrackingId: "tracking-id-7",
	}

	quotaResp, err := GetQuotaRemaining(ctx, client, userID, PREMIUM_REQUESTS, userDetails)
	require.NoError(t, err)
	require.Equal(t, int32(0), quotaResp.Remaining)
	require.Equal(t, int32(0), quotaResp.Total)
	require.False(t, quotaResp.OveragePermitted, "overage should be false when OveragePermitted is false")
	require.True(t, quotaResp.Unlimited, "unlimited should be true when Unlimited flag is set")
}

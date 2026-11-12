package githubtwirp

import (
	"context"
	"errors"
	"testing"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func boolPtr(v bool) *bool {
	return &v
}

func stringPtr(v string) *string {
	return &v
}

func TestComposeQuotaSnapshot_ReturnsComposedSnapshot(t *testing.T) {
	ctx := context.Background()
	userID := int64(90210)

	client := NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				Id:                  uint64(userID),
				AnalyticsTrackingId: "tracking-id-quota-snapshot",
				CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			},
		}, nil
	}

	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			TokenBasedBilling: boolPtr(false),
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{{
				QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
				Remaining:        3,
				Entitlement:      10,
				PercentRemaining: 0.3,
			}},
		}, nil
	}

	client.NoopBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).
		Return(&billingProto.CanProceedWithUsageResponse{CanProceed: true}, nil)

	snapshot := ComposeQuotaSnapshot(ctx, client, featureflags.NewNoopClient(map[string]bool{}), observability.NewNoopExporters(), 0, 0, userID)

	require.Equal(t, int32(3), snapshot.Remaining)
	require.Equal(t, 0.3, snapshot.PercentageRemaining)
	require.True(t, snapshot.CanStartSession)
	require.False(t, snapshot.Unlimited)
	require.Equal(t, CopilotForBusiness.String(), snapshot.CopilotPlan)
}

func TestComposeQuotaSnapshot_UsesFallbacksWhenDependenciesFail(t *testing.T) {
	ctx := context.Background()
	userID := int64(90211)

	client := NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return nil, errors.New("user detail fetch failed")
	}

	snapshot := ComposeQuotaSnapshot(ctx, client, featureflags.NewNoopClient(map[string]bool{}), observability.NewNoopExporters(), 0, 0, userID)

	require.Equal(t, int32(-1), snapshot.Remaining)
	require.Equal(t, -1.0, snapshot.PercentageRemaining)
	require.True(t, snapshot.CanStartSession)
	require.False(t, snapshot.Unlimited)
	require.Contains(t, []string{"", CopilotPlanInvalid.String()}, snapshot.CopilotPlan)
}

func TestGetQuotaRemaining_UsesProvidedUserDetails(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	ctx = requestid.WithGitHubRequestID(ctx, "req-123")
	userID := int64(44)
	require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{ID: "interaction-1"}))

	client := NewNoopClient()
	client.CopilotIntegrationIDValue = stringPtr("copilot-developer")
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return nil, errors.New("unexpected user details fetch")
	}

	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id-3", req.GetCopilotTrackingId())
		require.Equal(t, "copilot-developer", req.GetIntegrationId())
		require.Equal(t, "req-123", req.GetInteractionId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			TokenBasedBilling: boolPtr(true),
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

	quotaResp, fromCache, err := GetQuotaRemaining(ctx, client, userID, userDetails, false)
	require.NoError(t, err)
	require.False(t, fromCache)
	require.Equal(t, int32(5), quotaResp.Remaining)
	require.Equal(t, int32(10), quotaResp.Total)
	require.True(t, quotaResp.OveragePermitted)
	require.False(t, quotaResp.Unlimited)
	require.True(t, quotaResp.TokenBasedBilling)
}

func TestGetQuotaRemaining_OmitsInteractionIDWhenRequestIDMissing(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	userID := int64(55)
	require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{ID: "interaction-55"}))

	client := NewNoopClient()
	client.CopilotIntegrationIDValue = stringPtr("copilot-developer")
	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id-55", req.GetCopilotTrackingId())
		require.Equal(t, "", req.GetInteractionId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			TokenBasedBilling: boolPtr(false),
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{{
				QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
				Remaining:   1,
				Entitlement: 1,
			}},
		}, nil
	}

	userDetails := &copilotUsersTwirp.CopilotUserDetails{
		Id:                  uint64(userID),
		AnalyticsTrackingId: "tracking-id-55",
	}

	_, _, err := GetQuotaRemaining(ctx, client, userID, userDetails, false)
	require.NoError(t, err)
}

func TestGetQuotaRemaining_OmitsOptionalLimiterIDsWhenContextDataMissing(t *testing.T) {
	ctx := context.Background()
	userID := int64(54)
	client := NewNoopClient()
	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id-13", req.GetCopilotTrackingId())
		require.Equal(t, "", req.GetIntegrationId())
		require.Equal(t, "", req.GetInteractionId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			TokenBasedBilling: boolPtr(false),
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
				{
					QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					Remaining:   2,
					Entitlement: 8,
				},
			},
		}, nil
	}

	userDetails := &copilotUsersTwirp.CopilotUserDetails{
		Id:                  uint64(userID),
		AnalyticsTrackingId: "tracking-id-13",
	}

	quotaResp, fromCache, err := GetQuotaRemaining(ctx, client, userID, userDetails, false)
	require.NoError(t, err)
	require.False(t, fromCache)
	require.Equal(t, int32(2), quotaResp.Remaining)
	require.Equal(t, int32(8), quotaResp.Total)
}

func TestGetQuotaRemaining_UsesResponseLevelTokenBasedBilling(t *testing.T) {
	ctx := context.Background()
	userID := int64(53)

	client := NewNoopClient()
	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		require.Equal(t, "tracking-id-12", req.GetCopilotTrackingId())
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			TokenBasedBilling: boolPtr(false),
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
				{
					QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					Remaining:   3,
					Entitlement: 9,
				},
			},
		}, nil
	}

	userDetails := &copilotUsersTwirp.CopilotUserDetails{
		Id:                  uint64(userID),
		AnalyticsTrackingId: "tracking-id-12",
	}

	quotaResp, fromCache, err := GetQuotaRemaining(ctx, client, userID, userDetails, false)
	require.NoError(t, err)
	require.False(t, fromCache)
	require.False(t, quotaResp.TokenBasedBilling)
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

	hasQuota, totalQuota, tokenBasedBilling, err := CheckPremiumQuota(ctx, client, ffClient, observability.NewNoopExporters(), 1, 2, userID, false)
	require.NoError(t, err)
	require.True(t, hasQuota)
	require.Equal(t, int32(12), totalQuota)
	require.False(t, tokenBasedBilling)
}

func TestCheckPremiumQuota_CachesCanProceedWithUsageResult(t *testing.T) {
	ctx := context.Background()
	userID := int64(76)

	client := NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				Id:                  uint64(userID),
				AnalyticsTrackingId: "tracking-id-cache-can-proceed",
				CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasPaidAccess:       true,
			},
		}, nil
	}

	client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
		return &copilotLimitersTwirp.GetQuotaRemainingResponse{
			QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{{
				QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
				Remaining:        0,
				Entitlement:      5,
				OveragePermitted: true,
			}},
		}, nil
	}

	client.NoopBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).
		Return(&billingProto.CanProceedWithUsageResponse{CanProceed: true}, nil)

	ffClient := featureflags.NewNoopClient(map[string]bool{})

	hasQuota, _, _, err := CheckPremiumQuota(ctx, client, ffClient, observability.NewNoopExporters(), 1, 2, userID, true)
	require.NoError(t, err)
	require.True(t, hasQuota)

	cachedQuota, fromCache, err := GetQuotaRemaining(ctx, client, userID, nil, true)
	require.NoError(t, err)
	require.True(t, fromCache)
	require.NotNil(t, cachedQuota.CanProceedWithUsage)
	require.True(t, *cachedQuota.CanProceedWithUsage)
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

	hasQuota, totalQuota, _, err := CheckPremiumQuota(ctx, client, ffClient, observability.NewNoopExporters(), 1, 2, userID, false)
	require.NoError(t, err)
	require.True(t, hasQuota, "user with unlimited quota should be allowed to proceed even when CanProceedWithUsage returns false")
	require.Equal(t, int32(0), totalQuota)
}

func TestCheckPremiumQuota_PaidPlanTBBUsesAIUThreshold(t *testing.T) {
	t.Run("remaining below AIU threshold denies when canProceed is false", func(t *testing.T) {
		userID := int64(49)
		ctx := context.Background()

		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  uint64(userID),
					AnalyticsTrackingId: "tracking-id-8",
					CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
					HasPaidAccess:       true,
				},
			}, nil
		}

		client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
			require.Equal(t, "tracking-id-8", req.GetCopilotTrackingId())
			return &copilotLimitersTwirp.GetQuotaRemainingResponse{
				TokenBasedBilling: boolPtr(true),
				QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
					{
						QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
						Remaining:   6,
						Entitlement: 20,
					},
				},
			}, nil
		}

		client.NoopBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).
			Return(&billingProto.CanProceedWithUsageResponse{CanProceed: false}, nil).
			Once()

		ffClient := featureflags.NewNoopClient(map[string]bool{})

		hasQuota, totalQuota, tokenBasedBilling, err := CheckPremiumQuota(ctx, client, ffClient, observability.NewNoopExporters(), 1, 2, userID, false)
		require.NoError(t, err)
		require.False(t, hasQuota)
		require.Equal(t, int32(20), totalQuota)
		require.True(t, tokenBasedBilling)
	})

	t.Run("remaining at AIU threshold allows when canProceed is false", func(t *testing.T) {
		userID := int64(50)
		ctx := context.Background()

		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  uint64(userID),
					AnalyticsTrackingId: "tracking-id-9",
					CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
					HasPaidAccess:       true,
				},
			}, nil
		}

		client.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
			require.Equal(t, "tracking-id-9", req.GetCopilotTrackingId())
			return &copilotLimitersTwirp.GetQuotaRemainingResponse{
				TokenBasedBilling: boolPtr(true),
				QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
					{
						QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
						Remaining:   7,
						Entitlement: 30,
					},
				},
			}, nil
		}

		client.NoopBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).
			Return(&billingProto.CanProceedWithUsageResponse{CanProceed: false}, nil).
			Once()

		ffClient := featureflags.NewNoopClient(map[string]bool{})

		hasQuota, totalQuota, tokenBasedBilling, err := CheckPremiumQuota(ctx, client, ffClient, observability.NewNoopExporters(), 1, 2, userID, false)
		require.NoError(t, err)
		require.True(t, hasQuota)
		require.Equal(t, int32(30), totalQuota)
		require.True(t, tokenBasedBilling)
	})
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

	quotaResp, fromCache, err := GetQuotaRemaining(ctx, client, userID, userDetails, false)
	require.NoError(t, err)
	require.False(t, fromCache)
	require.Equal(t, int32(0), quotaResp.Remaining)
	require.Equal(t, int32(0), quotaResp.Total)
	require.False(t, quotaResp.OveragePermitted, "overage should be false when OveragePermitted is false")
	require.True(t, quotaResp.Unlimited, "unlimited should be true when Unlimited flag is set")
}

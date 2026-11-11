package twirpserver

import (
	"context"
	"errors"
	"testing"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestCheckQuota_SufficientQuota(t *testing.T) {
	ctx := t.Context()

	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: true,
	}, nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        100,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 10.0,
						},
					},
				}, nil
			},
		},
		NoopBillingClient: mockBillingClient,
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "task")
	require.NoError(t, err)
}

func TestCheckQuota_InsufficientQuota(t *testing.T) {
	ctx := t.Context()

	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: false,
	}, nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        0,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 0.0,
							OveragePermitted: false,
						},
					},
				}, nil
			},
		},
		NoopBillingClient: mockBillingClient,
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "task")
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.FailedPrecondition, twerr.Code())
	require.Contains(t, twerr.Msg(), "insufficient premium quota to create task")
}

func TestCheckQuota_InsufficientQuota_Command(t *testing.T) {
	ctx := t.Context()

	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: false,
	}, nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        0,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 0.0,
							OveragePermitted: false,
						},
					},
				}, nil
			},
		},
		NoopBillingClient: mockBillingClient,
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "command")
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.FailedPrecondition, twerr.Code())
	require.Contains(t, twerr.Msg(), "insufficient premium quota to create command")
}

func TestCheckQuota_QuotaCheckError(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return nil, errors.New("limiter service unavailable")
			},
		},
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "command")
	require.Error(t, err)
	require.Contains(t, err.Error(), "failed to check quota")
}

func TestCheckQuota_CustomerSelectionRequired_FeatureFlagEnabled(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        100,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 10.0,
						},
					},
				}, nil
			},
			MockGetConsumptiveUser: func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
				return &copilotLimitersTwirp.GetConsumptiveUserResponse{
					CustomerIds: []int64{},
					AccessType:  copilotLimitersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA,
				}, nil
			},
		},
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentSelectCustomerError: true,
	})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "task")
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.FailedPrecondition, twerr.Code())
	require.Contains(t, twerr.Msg(), "customer selection required")
}

func TestCheckQuota_CustomerSelectionRequired_FeatureFlagDisabled(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        100,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 10.0,
						},
					},
				}, nil
			},
			MockGetConsumptiveUser: func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
				return &copilotLimitersTwirp.GetConsumptiveUserResponse{
					CustomerIds: []int64{},
					AccessType:  copilotLimitersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA,
				}, nil
			},
		},
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentSelectCustomerError: false,
	})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "task")
	require.NoError(t, err)
}

func TestIsAgentCheckExempt(t *testing.T) {
	codeScanningApp := agenticapp.NewCodeScanning(12345, "github-advanced-security", 999, "github-advanced-security[bot]", "commit", "commit@email.com")
	provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 1, codeScanningApp)
	repoID := int64(42)

	t.Run("returns false for zero agent ID", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIntegrationQuotaExempt: true,
		})
		require.False(t, provider.IsAgentCheckExempt(t.Context(), ffClient, 0, repoID))
	})

	t.Run("returns true when flag is enabled for quota-exempt app", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIntegrationQuotaExempt: true,
		})
		require.True(t, provider.IsAgentCheckExempt(t.Context(), ffClient, 12345, repoID))
	})

	t.Run("returns false when flag is enabled but app is not quota-exempt", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIntegrationQuotaExempt: true,
		})
		// Copilot app (ID 1) is not quota-exempt
		require.False(t, provider.IsAgentCheckExempt(t.Context(), ffClient, 1, repoID))
	})

	t.Run("returns false when flag is disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIntegrationQuotaExempt: false,
		})
		require.False(t, provider.IsAgentCheckExempt(t.Context(), ffClient, 12345, repoID))
	})

	t.Run("returns false when flag is not set", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		require.False(t, provider.IsAgentCheckExempt(t.Context(), ffClient, 12345, repoID))
	})

	t.Run("returns false when app is not found", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIntegrationQuotaExempt: true,
		})
		require.False(t, provider.IsAgentCheckExempt(t.Context(), ffClient, 99999, repoID))
	})
}

func TestCheckQuota_FailOpen_TransientError_FlagEnabled(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return nil, twirp.NewError(twirp.Unavailable, "limiter service down")
			},
		},
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentLimiterFailOpen: true,
	})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "assignment")
	require.NoError(t, err, "should fail open on transient error when flag is enabled")
}

func TestCheckQuota_FailOpen_TransientError_FlagDisabled(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return nil, twirp.NewError(twirp.Unavailable, "limiter service down")
			},
		},
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentLimiterFailOpen: false,
	})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "assignment")
	require.Error(t, err, "should fail closed when flag is disabled")
	require.Contains(t, err.Error(), "failed to check quota")
}

func TestCheckQuota_FailOpen_NonTransientError_FlagEnabled(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				// FailedPrecondition is not transient — should remain fail-closed
				return nil, twirp.FailedPrecondition.Error("bad data")
			},
		},
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentLimiterFailOpen: true,
	})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "job")
	require.Error(t, err, "non-transient errors should remain fail-closed even with flag enabled")
	require.Contains(t, err.Error(), "failed to check quota")
}

func TestCheckQuota_FailOpen_CustomerSelectionError_FlagEnabled(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        100,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 10.0,
						},
					},
				}, nil
			},
			MockGetConsumptiveUser: func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
				return &copilotLimitersTwirp.GetConsumptiveUserResponse{
					CustomerIds: []int64{},
					AccessType:  copilotLimitersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA,
				}, nil
			},
		},
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentLimiterFailOpen:     true,
		featureflags.CopilotSWEAgentSelectCustomerError: true,
	})

	err := CheckQuota(ctx, mockGhTwirp, ffClient, obsv, 1, 2, 42, "task")
	require.Error(t, err, "customer selection errors should never fail open")

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.FailedPrecondition, twerr.Code())
	require.Contains(t, twerr.Msg(), "customer selection required")
}

package agentcallback

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestHandleCheckQuota_TokenBasedBillingUsesMedianAIUThreshold(t *testing.T) {
	type tc struct {
		name      string
		remaining int32
		expected  bool
	}

	testCases := []tc{
		{
			name:      "below threshold denies",
			remaining: 6,
			expected:  false,
		},
		{
			name:      "at threshold allows",
			remaining: 7,
			expected:  true,
		},
	}

	for _, tt := range testCases {
		t.Run(tt.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(nil)
			obsv := observability.NewNoopExporters()
			jobStore := memory.NewStore()
			cf := &github.NoopClientFactory{}
			noopClient := githubtwirp.NewNoopClient()
			noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsAgentEnabled: true,
			})
			jobService := &mockJobService{store: jobStore}
			capiClient := capi.NewNoopClient()
			appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
			h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

			ctx := addUserToContext(context.Background(), t)
			nonce, nonceHash := jobNonce()

			mockBillingClient := billingMocks.NewMockClientInterface(t)
			mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Return(&billingProto.CanProceedWithUsageResponse{
				CanProceed: false,
			}, nil)
			noopClient.NoopBillingClient = mockBillingClient

			noopClient.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					TokenBasedBilling: to.Ptr(true),
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							Remaining:   tt.remaining,
							Entitlement: 20,
						},
						{
							QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_IMMEDIATE_USAGE_INTERVAL,
							Remaining:   tt.remaining,
							Entitlement: 20,
						},
						{
							QuotaType:   copilotLimitersTwirp.QuotaType_QUOTA_TYPE_EXTENDED_USAGE_INTERVAL,
							Remaining:   100,
							Entitlement: 200,
						},
					},
				}, nil
			}

			job := &jobs.Job{
				ID:           "job-id-check-quota-threshold",
				AssignmentID: "assignment-id",
				OwnerID:      1,
				RepoID:       2,
				ActorID:      1,
				NonceHash:    nonceHash,
			}
			jobStore.CreateJob(ctx, job)

			update := JobUpdate{
				RepoID:      job.RepoID,
				RepoOwnerID: job.OwnerID,
				JobID:       job.ID,
				Kind:        AgentUpdateKindCheckQuota,
				Content:     `{}`,
			}
			b, _ := json.Marshal(update)

			req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
			req.Header.Set(jobs.JobNonceHeader, nonce)
			w := httptest.NewRecorder()
			h.HandleCallback(w, req)
			require.Equal(t, http.StatusOK, w.Code)

			var responseBody map[string]any
			err := json.Unmarshal(w.Body.Bytes(), &responseBody)
			require.NoError(t, err)
			require.Equal(t, tt.expected, responseBody["has_enough_quota"])
		})
	}
}

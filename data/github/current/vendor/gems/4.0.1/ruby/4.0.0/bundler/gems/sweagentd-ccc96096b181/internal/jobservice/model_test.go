package jobservice

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	jobExperiments "github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
)

func Test_DetermineModel(t *testing.T) {
	var mockTwirpClientForIndividualUser = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
		HasPaidAccess: true,
	})

	var mockTwirpClientForEnterpriseUser = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	tests := []struct {
		name            string
		variantValue    any
		ffs             map[string]bool
		requestedModel  string
		availableModels []capi.Model
		expectedModel   string
		expectedError   error
		twirpClient     githubtwirp.ClientInterface
	}{
		{
			name:          "Returns default model when variant is 1 (no experimental model configured)",
			variantValue:  1,
			expectedModel: CapiModelPrefix + capi.ClaudeSonnet45,
		},
		{
			name:          "Returns default model when variant is 2 (no experimental model configured)",
			variantValue:  2,
			expectedModel: CapiModelPrefix + capi.ClaudeSonnet45,
		},
		{
			name:          "Returns default model when variant is a string",
			variantValue:  "string",
			expectedModel: CapiModelPrefix + capi.ClaudeSonnet45,
		},
		{
			name:          "Returns default model when variant is nil",
			variantValue:  nil,
			expectedModel: CapiModelPrefix + capi.ClaudeSonnet45,
		},
		{
			name:           "model selection for individual plan with available model",
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: "sweagent-capi:claude-opus-4.5",
			twirpClient:   mockTwirpClientForIndividualUser,
		},
		{
			name:           "model selection for individual plan without prefix",
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: "sweagent-capi:claude-opus-4.5",
			twirpClient:   mockTwirpClientForIndividualUser,
		},
		{
			name:           "model not available returns error for individual plan",
			requestedModel: "sweagent-capi:claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedError: ErrModelNotFound,
			twirpClient:   mockTwirpClientForIndividualUser,
		},
		{
			name:           "enterprise plan without all-SKUs flag falls back to auto",
			requestedModel: "sweagent-capi:claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5"},
				{ID: "claude-opus-4.5"},
			},
			expectedModel: CapiModelPrefix + capi.ClaudeSonnet45,
			twirpClient:   mockTwirpClientForEnterpriseUser,
		},
		{
			name: "with staff flag enabled allows non-CAPI model (individual plan)",
			ffs: map[string]bool{
				featureflags.CopilotSWEAgentCanSelectModel: true,
			},
			requestedModel: "azopenai:custom-model",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: "azopenai:custom-model",
			twirpClient:   mockTwirpClientForIndividualUser,
		},
		{
			name: "with staff flag enabled skips validation for non-CAPI or unlisted CAPI models",
			ffs: map[string]bool{
				featureflags.CopilotSWEAgentCanSelectModel: true,
			},
			requestedModel: "sweagent-capi:not-a-real-model",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: "sweagent-capi:not-a-real-model",
			twirpClient:   mockTwirpClientForIndividualUser,
		},
		{
			name:           "without staff flag returns error for non-CAPI model (individual plan)",
			requestedModel: "azopenai:custom-model",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedError: ErrModelNotFound,
			twirpClient:   mockTwirpClientForIndividualUser,
		},
		{
			name: "with all-SKUs flag enabled allows model selection for business plan",
			ffs: map[string]bool{
				featureflags.CodingAgentModelSelectionAllSKUs: true,
			},
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: "sweagent-capi:claude-opus-4.5",
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			}),
		},
		{
			name: "with all-SKUs flag enabled allows model selection for enterprise plan",
			ffs: map[string]bool{
				featureflags.CodingAgentModelSelectionAllSKUs: true,
			},
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: "sweagent-capi:claude-opus-4.5",
			twirpClient:   mockTwirpClientForEnterpriseUser,
		},
		{
			name: "with all-SKUs flag enabled allows model selection for free plan",
			ffs: map[string]bool{
				featureflags.CodingAgentModelSelectionAllSKUs: true,
			},
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: "sweagent-capi:claude-opus-4.5",
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:      copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasFreeAccess:    true,
				HasLimitedAccess: true,
			}),
		},
		{
			name: "with all-SKUs flag enabled allows model selection for trial plan",
			ffs: map[string]bool{
				featureflags.CodingAgentModelSelectionAllSKUs: true,
			},
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: "sweagent-capi:claude-opus-4.5",
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			}),
		},
		{
			name:           "without all-SKUs flag, model selection is still restricted for business plan",
			requestedModel: "sweagent-capi:claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: CapiModelPrefix + capi.ClaudeSonnet45,
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			}),
		},
		{
			name: "free user with experiment flag enabled returns Sonnet",
			ffs: map[string]bool{
				featureflags.CodingAgentFreeUsersExperiment: true,
			},
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: CapiModelPrefix + capi.ClaudeSonnet45,
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:      copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasFreeAccess:    true,
				HasLimitedAccess: true,
			}),
		},
		{
			name: "free user with experiment flag disabled returns error",
			ffs: map[string]bool{
				featureflags.CodingAgentFreeUsersExperiment: false,
			},
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedError: ErrNoModelAvailable,
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:      copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasFreeAccess:    true,
				HasLimitedAccess: true,
			}),
		},
		{
			name: "individual user with experiment flag can access other models as normal",
			ffs: map[string]bool{
				featureflags.CodingAgentFreeUsersExperiment: true,
			},
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: CapiModelPrefix + capi.ClaudeOpus45,
			twirpClient:   mockTwirpClientForIndividualUser,
		},
		{
			name: "enterprise user with experiment flag can access other models as normal",
			ffs: map[string]bool{
				featureflags.CodingAgentFreeUsersExperiment:   true,
				featureflags.CodingAgentModelSelectionAllSKUs: true,
			},
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel: CapiModelPrefix + capi.ClaudeOpus45,
			twirpClient:   mockTwirpClientForEnterpriseUser,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			obsv := observability.NewNoopExporters()
			ffs := featureflags.NewNoopClient(tt.ffs)
			pr := eventstest.PullRequest()
			job := eventstest.Assignment().NewJob(
				jobs.AgentActionFixPRComment,
				jobs.JobActor{
					ID:         eventstest.UserWriter().ID,
					Login:      eventstest.UserWriter().Login,
					TrackingID: "tracking-id",
				},
				pr.HeadRef.Name,
			)
			if tt.variantValue != nil {
				job.Experiments = &jobExperiments.AssignmentExperiments{
					Variations: map[string]any{
						experiments.ModelCompareExperiment: tt.variantValue,
					},
				}
			}

			capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
			if tt.availableModels != nil {
				capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
					return tt.availableModels, nil
				}
			}
			twirpClient := tt.twirpClient
			if twirpClient == nil {
				twirpClient = mockTwirpClientForEnterpriseUser
			}
			s := New(obsv, ffs, store, capiClient, gcf, twirpClient, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

			model, err := s.DetermineModel(ctx, tt.requestedModel, job)
			if tt.expectedError != nil {
				require.ErrorIs(t, err, tt.expectedError)
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.expectedModel, model)
			}
		})
	}

	t.Run("uses Opus for CfB/Enterprise users when FF and Lotus policy are enabled", func(t *testing.T) {
		var mockTwirpClientForBusinessUserWithLotus = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan:  copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			LotusSetting: copilotUsersTwirp.Lotus_LOTUS_ENABLED,
		})

		var mockTwirpClientForBusinessUserWithoutLotus = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan:  copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			LotusSetting: copilotUsersTwirp.Lotus_LOTUS_DISABLED,
		})

		var mockTwirpClientForEnterpriseUserWithLotus = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan:  copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
			LotusSetting: copilotUsersTwirp.Lotus_LOTUS_ENABLED,
		})

		userDetailsError := errors.New("error fetching copilot user details")

		for name, tt := range map[string]struct {
			client        githubtwirp.ClientInterface
			ffs           map[string]bool
			expected      string
			expectedError error
		}{
			"business user with Lotus enabled and FF enabled": {
				client:   mockTwirpClientForBusinessUserWithLotus,
				ffs:      map[string]bool{"copilot_swe_agent_use_opus_model_for_cfb_users_with_policy_enabled": true},
				expected: CapiModelPrefix + capi.ClaudeOpus45,
			},
			"business user with Lotus disabled and FF enabled": {
				client:   mockTwirpClientForBusinessUserWithoutLotus,
				ffs:      map[string]bool{"copilot_swe_agent_use_opus_model_for_cfb_users_with_policy_enabled": true},
				expected: CapiModelPrefix + capi.ClaudeSonnet45,
			},
			"business user with Lotus enabled but FF disabled": {
				client:   mockTwirpClientForBusinessUserWithLotus,
				ffs:      nil,
				expected: CapiModelPrefix + capi.ClaudeSonnet45,
			},
			"enterprise user with Lotus enabled and FF enabled": {
				client:   mockTwirpClientForEnterpriseUserWithLotus,
				ffs:      map[string]bool{"copilot_swe_agent_use_opus_model_for_cfb_users_with_policy_enabled": true},
				expected: CapiModelPrefix + capi.ClaudeOpus45,
			},
			"error fetching user details": {
				client: func() githubtwirp.ClientInterface {
					client := githubtwirp.NewNoopClient()
					client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
						return nil, userDetailsError
					}
					return client
				}(),
				ffs:           map[string]bool{"copilot_swe_agent_use_opus_model_for_cfb_users_with_policy_enabled": true},
				expectedError: userDetailsError,
			},
		} {
			t.Run(name, func(t *testing.T) {
				ctx := context.Background()
				obsv := observability.NewNoopExporters()
				ffs := featureflags.NewNoopClient(tt.ffs)
				job := eventstest.Assignment().NewJob(
					jobs.AgentActionFixPRComment,
					jobs.JobActor{
						ID:         eventstest.UserWriter().ID,
						Login:      eventstest.UserWriter().Login,
						TrackingID: "tracking-id",
					},
					eventstest.PullRequest().HeadRef.Name,
				)

				capi, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
				s := New(obsv, ffs, store, capi, gcf, tt.client, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

				model, err := s.DetermineModel(ctx, "", job)
				if tt.expectedError != nil {
					require.ErrorIs(t, err, tt.expectedError)
				} else {
					require.NoError(t, err)
					require.Equal(t, tt.expected, model)
				}
			})
		}
	})

	t.Run("uses Opus for individual users when FF is enabled", func(t *testing.T) {
		var mockTwirpClientForIndividualUser = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
		})

		var mockTwirpClientForProPlusUser = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
		})

		for name, tt := range map[string]struct {
			client   githubtwirp.ClientInterface
			ffs      map[string]bool
			expected string
		}{
			"individual user with FF enabled": {
				client:   mockTwirpClientForIndividualUser,
				ffs:      map[string]bool{"copilot_swe_agent_use_opus_model_for_individual_users": true},
				expected: CapiModelPrefix + capi.ClaudeOpus45,
			},
			"individual user with FF disabled": {
				client:   mockTwirpClientForIndividualUser,
				ffs:      nil,
				expected: CapiModelPrefix + capi.ClaudeSonnet45,
			},
			"pro plus user with FF enabled": {
				client:   mockTwirpClientForProPlusUser,
				ffs:      map[string]bool{"copilot_swe_agent_use_opus_model_for_individual_users": true},
				expected: CapiModelPrefix + capi.ClaudeOpus45,
			},
			"pro plus user with FF disabled": {
				client:   mockTwirpClientForProPlusUser,
				ffs:      nil,
				expected: CapiModelPrefix + capi.ClaudeSonnet45,
			},
		} {
			t.Run(name, func(t *testing.T) {
				ctx := context.Background()
				obsv := observability.NewNoopExporters()
				ffs := featureflags.NewNoopClient(tt.ffs)
				job := eventstest.Assignment().NewJob(
					jobs.AgentActionFixPRComment,
					jobs.JobActor{
						ID:         eventstest.UserWriter().ID,
						Login:      eventstest.UserWriter().Login,
						TrackingID: "tracking-id",
					},
					eventstest.PullRequest().HeadRef.Name,
				)

				capi, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
				s := New(obsv, ffs, store, capi, gcf, tt.client, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

				model, err := s.DetermineModel(ctx, "", job)
				require.NoError(t, err)
				require.Equal(t, tt.expected, model)
			})
		}
	})
}

func Test_userCanAccessModel(t *testing.T) {
	tests := []struct {
		name           string
		requestedModel string
		models         []capi.Model
		expected       bool
	}{
		{
			name:           "model with Policy.State = Disabled is not accessible",
			requestedModel: "claude-opus-4.5",
			models: []capi.Model{
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateDisabled}},
			},
			expected: false,
		},
		{
			name:           "model with Policy.State = Enabled is accessible",
			requestedModel: "claude-opus-4.5",
			models: []capi.Model{
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expected: true,
		},
		{
			name:           "model with Policy.State = Unconfigured is accessible",
			requestedModel: "claude-opus-4.5",
			models: []capi.Model{
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateUnconfigured}},
			},
			expected: true,
		},
		{
			name:           "model with Policy = nil is not accessible",
			requestedModel: "claude-opus-4.5",
			models: []capi.Model{
				{ID: "claude-opus-4.5", Policy: nil},
			},
			expected: false,
		},
		{
			name:           "model with empty Policy.State is not accessible",
			requestedModel: "claude-opus-4.5",
			models: []capi.Model{
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: ""}},
			},
			expected: false,
		},
		{
			name:           "model not in list is not accessible",
			requestedModel: "claude-opus-4.5",
			models: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expected: false,
		},
		{
			name:           "finds correct model when multiple models in list",
			requestedModel: "claude-opus-4.5",
			models: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "gpt-5.1-codex-max", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateDisabled}},
			},
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := userCanAccessModel(tt.requestedModel, tt.models)
			require.Equal(t, tt.expected, result)
		})
	}
}

func Test_mustUseAutoModel(t *testing.T) {
	tests := []struct {
		name     string
		plan     githubtwirp.CopilotPlan
		ffs      map[string]bool
		expected bool
	}{
		{
			name:     "returns false for individual plan (model selection always allowed)",
			plan:     githubtwirp.CopilotForIndividual,
			ffs:      nil,
			expected: false,
		},
		{
			name:     "returns true for business plan without all-SKUs flag",
			plan:     githubtwirp.CopilotForBusiness,
			ffs:      nil,
			expected: true,
		},
		{
			name:     "returns true for enterprise plan without all-SKUs flag",
			plan:     githubtwirp.CopilotForEnterprise,
			ffs:      nil,
			expected: true,
		},
		{
			name:     "returns true for individual free plan without all-SKUs flag",
			plan:     githubtwirp.CopilotForIndividualFree,
			ffs:      nil,
			expected: true,
		},
		{
			name:     "returns true for individual trial plan without all-SKUs flag",
			plan:     githubtwirp.CopilotForIndividualTrial,
			ffs:      nil,
			expected: true,
		},
		{
			name:     "returns false for individual pro plus plan (model selection always allowed)",
			plan:     githubtwirp.CopilotForIndividualProPlus,
			ffs:      nil,
			expected: false,
		},
		{
			name: "returns false for business plan with all-SKUs flag enabled",
			plan: githubtwirp.CopilotForBusiness,
			ffs: map[string]bool{
				featureflags.CodingAgentModelSelectionAllSKUs: true,
			},
			expected: false,
		},
		{
			name: "returns false for enterprise plan with all-SKUs flag enabled",
			plan: githubtwirp.CopilotForEnterprise,
			ffs: map[string]bool{
				featureflags.CodingAgentModelSelectionAllSKUs: true,
			},
			expected: false,
		},
		{
			name: "returns false for individual free plan with all-SKUs flag enabled",
			plan: githubtwirp.CopilotForIndividualFree,
			ffs: map[string]bool{
				featureflags.CodingAgentModelSelectionAllSKUs: true,
			},
			expected: false,
		},
		{
			name: "returns false for individual trial plan with all-SKUs flag enabled",
			plan: githubtwirp.CopilotForIndividualTrial,
			ffs: map[string]bool{
				featureflags.CodingAgentModelSelectionAllSKUs: true,
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			obsv := observability.NewNoopExporters()
			ffs := featureflags.NewNoopClient(tt.ffs)
			job := eventstest.Assignment().NewJob(
				jobs.AgentActionFixPRComment,
				jobs.JobActor{
					ID:         eventstest.UserWriter().ID,
					Login:      eventstest.UserWriter().Login,
					TrackingID: "tracking-id",
				},
				eventstest.PullRequest().HeadRef.Name,
			)

			capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
			s := New(obsv, ffs, store, capiClient, gcf, nil, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

			result := s.mustUseAutoModel(ctx, tt.plan, job)
			require.Equal(t, tt.expected, result)
		})
	}
}

// newMockTwirpClientWithUserDetails returns a mock githubtwirp.ClientInterface that returns a response for GetCopilotUser
// with the provided CopilotUserDetails.
func newMockTwirpClientWithUserDetails(userDetails *copilotUsersTwirp.CopilotUserDetails) githubtwirp.ClientInterface {
	client := githubtwirp.NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: userDetails,
		}, nil
	}

	return client
}

func Test_stripModelPrefix(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "strips sweagent-capi prefix",
			input:    "sweagent-capi:claude-opus-4.5",
			expected: "claude-opus-4.5",
		},
		{
			name:     "strips sweagent-capi prefix from sonnet",
			input:    "sweagent-capi:claude-sonnet-4.5",
			expected: "claude-sonnet-4.5",
		},
		{
			name:     "returns unchanged if no prefix",
			input:    "claude-opus-4.5",
			expected: "claude-opus-4.5",
		},
		{
			name:     "returns unchanged for non-CAPI models",
			input:    "azopenai:gpt-4o",
			expected: "azopenai:gpt-4o",
		},
		{
			name:     "handles empty string",
			input:    "",
			expected: "",
		},
		{
			name:     "handles prefix only",
			input:    "sweagent-capi:",
			expected: "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := stripModelPrefix(tc.input)
			require.Equal(t, tc.expected, result)
		})
	}
}

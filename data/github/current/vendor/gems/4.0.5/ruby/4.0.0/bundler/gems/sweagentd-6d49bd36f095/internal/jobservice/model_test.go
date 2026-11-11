package jobservice

import (
	"context"
	"testing"

	"github.com/github/feature-management-client-go/githubexp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/events/eventstest"
	expSDK "github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	jobExperiments "github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
)

func Test_DetermineModel(t *testing.T) {
	individualUserDetails := &copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
		HasPaidAccess: true,
	}
	enterpriseUserDetails := &copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	}

	var mockTwirpClientForIndividualUser = newMockTwirpClientWithUserDetails(individualUserDetails)
	var mockTwirpClientForEnterpriseUser = newMockTwirpClientWithUserDetails(enterpriseUserDetails)

	tests := []struct {
		name               string
		experimentName     string
		variantValue       any
		sdkAssignment      map[string]string // ExP SDK feature variables to set in context
		ffs                map[string]bool
		requestedModel     string
		availableModels    []capi.Model
		expectedModel      string
		expectedIsAutoMode bool
		expectedError      error
		twirpClient        githubtwirp.ClientInterface
		userDetails        *copilotUsersTwirp.CopilotUserDetails
	}{
		{
			name:           "model selection for individual plan with available model",
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel:      "sweagent-capi:claude-opus-4.5",
			expectedIsAutoMode: false,
			twirpClient:        mockTwirpClientForIndividualUser,
			userDetails:        individualUserDetails,
		},
		{
			name:           "model selection for individual plan without prefix",
			requestedModel: "claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel:      "sweagent-capi:claude-opus-4.5",
			expectedIsAutoMode: false,
			twirpClient:        mockTwirpClientForIndividualUser,
			userDetails:        individualUserDetails,
		},
		{
			name:           "model not available returns error for individual plan",
			requestedModel: "sweagent-capi:claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedError: ErrModelNotFound,
			twirpClient:   mockTwirpClientForIndividualUser,
			userDetails:   individualUserDetails,
		},
		{
			name:           "enterprise plan without all-SKUs flag falls back to auto",
			requestedModel: "sweagent-capi:claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.6", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel:      capi.AutoMode,
			expectedIsAutoMode: true,
			twirpClient:        mockTwirpClientForEnterpriseUser,
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
			expectedModel:      "azopenai:custom-model",
			expectedIsAutoMode: false,
			twirpClient:        mockTwirpClientForIndividualUser,
			userDetails:        individualUserDetails,
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
			expectedModel:      "sweagent-capi:not-a-real-model",
			expectedIsAutoMode: false,
			twirpClient:        mockTwirpClientForIndividualUser,
			userDetails:        individualUserDetails,
		},
		{
			name:           "without staff flag returns error for non-CAPI model (individual plan)",
			requestedModel: "azopenai:custom-model",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedError: ErrModelNotFound,
			twirpClient:   mockTwirpClientForIndividualUser,
			userDetails:   individualUserDetails,
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
			expectedModel:      "sweagent-capi:claude-opus-4.5",
			expectedIsAutoMode: false,
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			}),
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			},
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
			expectedModel:      "sweagent-capi:claude-opus-4.5",
			expectedIsAutoMode: false,
			twirpClient:        mockTwirpClientForEnterpriseUser,
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
			expectedModel:      "sweagent-capi:claude-opus-4.5",
			expectedIsAutoMode: false,
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:      copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasFreeAccess:    true,
				HasLimitedAccess: true,
			}),
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:      copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasFreeAccess:    true,
				HasLimitedAccess: true,
			},
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
			expectedModel:      "sweagent-capi:claude-opus-4.5",
			expectedIsAutoMode: false,
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			}),
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			},
		},
		{
			name:           "without all-SKUs flag, business plan model selection falls back to auto",
			requestedModel: "sweagent-capi:claude-opus-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.6", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-sonnet-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-opus-4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel:      capi.AutoMode,
			expectedIsAutoMode: true,
			twirpClient: newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			}),
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			},
		},
		{
			name: "auto mode returns 'auto' (concrete model resolved by job-fetch handler)",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.6", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel:      capi.AutoMode,
			expectedIsAutoMode: true,
			twirpClient:        mockTwirpClientForIndividualUser,
			userDetails:        individualUserDetails,
		},
		{
			name:               "no models available for first-party agent falls back to GPT-5.3-Codex",
			availableModels:    []capi.Model{},
			expectedModel:      jobs.CapiModelPrefix + capi.GPT53Codex,
			expectedIsAutoMode: false,
			twirpClient:        mockTwirpClientForEnterpriseUser,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			if tt.sdkAssignment != nil {
				ctx = expSDK.WithAssignment(ctx, githubexp.NewAssignmentResult(tt.sdkAssignment, "", 0))
			}
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
			if tt.variantValue != nil && tt.experimentName != "" {
				job.Experiments = &jobExperiments.AssignmentExperiments{
					Variations: map[string]any{
						tt.experimentName: tt.variantValue,
					},
				}
			}

			capiClient, store, _, gcf, expClient, aq, limiter := commonServiceDependencies(obsv)
			if tt.availableModels != nil {
				capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
					return tt.availableModels, nil
				}
			}
			twirpClient := tt.twirpClient
			if twirpClient == nil {
				twirpClient = mockTwirpClientForEnterpriseUser
			}
			userDetails := tt.userDetails
			if userDetails == nil {
				userDetails = enterpriseUserDetails
			}
			s := New(obsv, ffs, store, capiClient, gcf, twirpClient, aq, limiter, expClient, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

			model, err := s.DetermineModel(ctx, tt.requestedModel, job, 0, userDetails)
			if tt.expectedError != nil {
				require.ErrorIs(t, err, tt.expectedError)
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.expectedModel, model)
				require.Equal(t, tt.expectedIsAutoMode, job.IsAutoMode, "job.IsAutoMode should match expected value")
			}
		})
	}
}

type counterCall struct {
	key   string
	tags  stats.Tags
	value int64
}

func Test_autoModelExperimentMetrics(t *testing.T) {
	// Verifies that autoModelExperimentModel emits the
	// jobservice.auto_model_experiment metric with the correct variant tag.

	newService := func(counterCalls *[]counterCall, ffs map[string]bool) *Service {
		obsv := observability.NewNoopExporters()
		mockStatter := &observability.MockStatter{}
		mockStatter.MockCounter = func(key string, tags stats.Tags, value int64) {
			*counterCalls = append(*counterCalls, counterCall{key, tags, value})
		}
		obsv.Statter = mockStatter

		if ffs == nil {
			ffs = map[string]bool{featureflags.CodingAgentAutoModelExperiment: true}
		}
		ffClient := featureflags.NewNoopClient(ffs)
		capiClient, store, _, gcf, expClient, aq, limiter := commonServiceDependencies(obsv)
		twirpClient := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
		})
		return New(obsv, ffClient, store, capiClient, gcf, twirpClient, aq, limiter, expClient, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
	}

	newJob := func() *jobs.Job {
		pr := eventstest.PullRequest()
		return eventstest.Assignment().NewJob(
			jobs.AgentActionFixPRComment,
			jobs.JobActor{
				ID:         eventstest.UserWriter().ID,
				Login:      eventstest.UserWriter().Login,
				TrackingID: "tracking-id",
			},
			pr.HeadRef.Name,
		)
	}

	filterExperimentMetrics := func(calls []counterCall) []counterCall {
		var filtered []counterCall
		for _, c := range calls {
			if c.key == "jobservice.auto_model_experiment" {
				filtered = append(filtered, c)
			}
		}
		return filtered
	}

	t.Run("control group emits metric with variant=control", func(t *testing.T) {
		var calls []counterCall
		s := newService(&calls, nil)
		ctx := expSDK.WithAssignment(context.Background(), githubexp.NewAssignmentResult(map[string]string{
			expSDK.FlagKey(expSDK.CopilotCodingAgentAutoModel["control"]): "true",
		}, "", 0))

		model, ok := s.autoModelExperimentModel(ctx, newJob())
		require.Equal(t, "", model)
		require.False(t, ok)

		filtered := filterExperimentMetrics(calls)
		require.Len(t, filtered, 1)
		require.Equal(t, "control", filtered[0].tags["variant"])
	})

	t.Run("var1 treatment returns model and emits metric", func(t *testing.T) {
		var calls []counterCall
		s := newService(&calls, nil)
		ctx := expSDK.WithAssignment(context.Background(), githubexp.NewAssignmentResult(map[string]string{
			expSDK.FlagKey(expSDK.CopilotCodingAgentAutoModel["var1"]): "true",
		}, "", 0))

		model, ok := s.autoModelExperimentModel(ctx, newJob())
		require.Equal(t, capi.GPT53Codex, model)
		require.True(t, ok)

		filtered := filterExperimentMetrics(calls)
		require.Len(t, filtered, 1)
		require.Equal(t, "var1", filtered[0].tags["variant"])
	})

	t.Run("var2 treatment returns model and emits metric", func(t *testing.T) {
		var calls []counterCall
		s := newService(&calls, nil)
		ctx := expSDK.WithAssignment(context.Background(), githubexp.NewAssignmentResult(map[string]string{
			expSDK.FlagKey(expSDK.CopilotCodingAgentAutoModel["var2"]): "true",
		}, "", 0))

		model, ok := s.autoModelExperimentModel(ctx, newJob())
		require.Equal(t, capi.ClaudeOpus46, model)
		require.True(t, ok)

		filtered := filterExperimentMetrics(calls)
		require.Len(t, filtered, 1)
		require.Equal(t, "var2", filtered[0].tags["variant"])
	})

	t.Run("no assignment emits no experiment metric", func(t *testing.T) {
		var calls []counterCall
		s := newService(&calls, nil)
		ctx := expSDK.WithAssignment(context.Background(), githubexp.NewAssignmentResult(map[string]string{}, "", 0))

		model, ok := s.autoModelExperimentModel(ctx, newJob())
		require.Equal(t, "", model)
		require.False(t, ok)

		filtered := filterExperimentMetrics(calls)
		require.Empty(t, filtered)
	})

	t.Run("multiple treatments enabled emits no metric", func(t *testing.T) {
		var calls []counterCall
		s := newService(&calls, nil)
		ctx := expSDK.WithAssignment(context.Background(), githubexp.NewAssignmentResult(map[string]string{
			expSDK.FlagKey(expSDK.CopilotCodingAgentAutoModel["var1"]): "true",
			expSDK.FlagKey(expSDK.CopilotCodingAgentAutoModel["var2"]): "true",
		}, "", 0))

		model, ok := s.autoModelExperimentModel(ctx, newJob())
		require.Equal(t, "", model)
		require.False(t, ok)

		filtered := filterExperimentMetrics(calls)
		require.Empty(t, filtered)
	})

	t.Run("feature flag disabled emits no metric", func(t *testing.T) {
		var calls []counterCall
		s := newService(&calls, map[string]bool{
			featureflags.CodingAgentAutoModelExperiment: false,
		})
		ctx := expSDK.WithAssignment(context.Background(), githubexp.NewAssignmentResult(map[string]string{
			expSDK.FlagKey(expSDK.CopilotCodingAgentAutoModel["var1"]): "true",
		}, "", 0))

		model, ok := s.autoModelExperimentModel(ctx, newJob())
		require.Equal(t, "", model)
		require.False(t, ok)

		filtered := filterExperimentMetrics(calls)
		require.Empty(t, filtered)
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
				{ID: "gpt-5.2-codex", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateDisabled}},
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

func Test_filterNonPremiumModels(t *testing.T) {
	tests := []struct {
		name     string
		models   []capi.Model
		expected []string
	}{
		{
			name: "filters out models with multiplier > 1",
			models: []capi.Model{
				{ID: "model-1x", Billing: &capi.ModelBilling{Multiplier: 1}},
				{ID: "model-3x", Billing: &capi.ModelBilling{Multiplier: 3}},
				{ID: "model-5x", Billing: &capi.ModelBilling{Multiplier: 5}},
			},
			expected: []string{"model-1x"},
		},
		{
			name: "keeps models without billing info",
			models: []capi.Model{
				{ID: "model-no-billing"},
				{ID: "model-3x", Billing: &capi.ModelBilling{Multiplier: 3}},
			},
			expected: []string{"model-no-billing"},
		},
		{
			name: "keeps all models when none are premium",
			models: []capi.Model{
				{ID: "model-a", Billing: &capi.ModelBilling{Multiplier: 1}},
				{ID: "model-b", Billing: &capi.ModelBilling{Multiplier: 0.5}},
				{ID: "model-c"},
			},
			expected: []string{"model-a", "model-b", "model-c"},
		},
		{
			name:     "returns empty for empty input",
			models:   []capi.Model{},
			expected: []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := filterNonPremiumModels(tt.models)
			ids := make([]string, len(result))
			for i, m := range result {
				ids[i] = m.ID
			}
			require.Equal(t, tt.expected, ids)
		})
	}
}

func Test_isPremiumModelInList(t *testing.T) {
	models := []capi.Model{
		{ID: "premium-model", Billing: &capi.ModelBilling{IsPremium: true, Multiplier: 3}},
		{ID: "standard-model", Billing: &capi.ModelBilling{IsPremium: false, Multiplier: 1}},
		{ID: "no-billing-model"},
	}

	require.True(t, isPremiumModelInList("premium-model", models))
	require.False(t, isPremiumModelInList("standard-model", models))
	require.False(t, isPremiumModelInList("no-billing-model", models))
	require.False(t, isPremiumModelInList("unknown-model", models))
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
			s := New(obsv, ffs, store, capiClient, gcf, nil, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

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

func Test_DetermineModel_ThirdPartyAgents(t *testing.T) {
	individualUserDetails := &copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
		HasPaidAccess: true,
	}
	var mockTwirpClientForIndividualUser = newMockTwirpClientWithUserDetails(individualUserDetails)

	anthropicVendor := sweagentd.ModelVendorAnthropic
	openaiVendor := sweagentd.ModelVendorOpenAI

	tests := []struct {
		name               string
		agentID            int64
		requestedModel     string
		availableModels    []capi.Model
		expectedModel      string
		expectedIsAutoMode bool
		expectedError      error
	}{
		{
			name:    "Claude agent auto mode selects from Anthropic models only",
			agentID: 100,
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel:      jobs.CapiModelPrefix + capi.ClaudeSonnet45,
			expectedIsAutoMode: true,
		},
		{
			name:           "Claude agent explicit model selection with Anthropic model succeeds",
			agentID:        100,
			requestedModel: "claude-sonnet-4.5",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel:      jobs.CapiModelPrefix + "claude-sonnet-4.5",
			expectedIsAutoMode: false,
		},
		{
			name:           "Claude agent explicit model selection with OpenAI model fails with vendor mismatch",
			agentID:        100,
			requestedModel: "gpt-5.2-codex",
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedError: ErrModelVendorMismatch,
		},
		{
			name:    "Codex agent auto mode selects from OpenAI models only",
			agentID: 200,
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel:      jobs.CapiModelPrefix + "gpt-5.2-codex",
			expectedIsAutoMode: true,
		},
		{
			name:    "Third-party agent with no matching vendor models returns error",
			agentID: 100,
			availableModels: []capi.Model{
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedError: ErrNoModelAvailable,
		},
		{
			name:           "Claude agent explicit OpenAI model with no Anthropic models returns vendor mismatch",
			agentID:        100,
			requestedModel: "gpt-5.2-codex",
			availableModels: []capi.Model{
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedError: ErrModelVendorMismatch,
		},
		{
			name:    "Third-party agent respects policy state disabled",
			agentID: 100,
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateDisabled}},
			},
			expectedError: ErrNoModelAvailable,
		},
		{
			name:    "Copilot agent (agentID=0) does not filter by vendor",
			agentID: 0,
			availableModels: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "claude-sonnet-4.6", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			},
			expectedModel:      capi.AutoMode,
			expectedIsAutoMode: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			obsv := observability.NewNoopExporters()
			ffs := featureflags.NewNoopClient(map[string]bool{
				featureflags.CodingAgentThirdPartyModelVendorFilter: true,
			})
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

			capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
			capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
				return tt.availableModels, nil
			}

			// Create third-party apps for testing
			claudeApp := agenticapptest.NewTestApp(100).WithModelVendors([]string{sweagentd.ModelVendorAnthropic})
			codexApp := agenticapptest.NewTestApp(200).WithModelVendors([]string{sweagentd.ModelVendorOpenAI})
			provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp, codexApp)

			s := New(obsv, ffs, store, capiClient, gcf, mockTwirpClientForIndividualUser, aq, limiter, exp, nil, "test_name", "test@example.com", nil, provider, nil)

			model, err := s.DetermineModel(ctx, tt.requestedModel, job, tt.agentID, individualUserDetails)
			if tt.expectedError != nil {
				require.ErrorIs(t, err, tt.expectedError)
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.expectedModel, model)
				require.Equal(t, tt.expectedIsAutoMode, job.IsAutoMode, "job.IsAutoMode should match expected value")
			}
		})
	}
}

func Test_filterModelsByVendors(t *testing.T) {
	anthropicVendor := sweagentd.ModelVendorAnthropic
	openaiVendor := sweagentd.ModelVendorOpenAI

	tests := []struct {
		name     string
		models   []capi.Model
		vendors  []string
		expected []capi.Model
	}{
		{
			name: "filters to Anthropic models only",
			models: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor},
				{ID: "claude-opus-4.5", Vendor: &anthropicVendor},
			},
			vendors: []string{sweagentd.ModelVendorAnthropic},
			expected: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor},
				{ID: "claude-opus-4.5", Vendor: &anthropicVendor},
			},
		},
		{
			name: "filters to OpenAI models only",
			models: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor},
			},
			vendors: []string{sweagentd.ModelVendorOpenAI},
			expected: []capi.Model{
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor},
			},
		},
		{
			name: "returns empty when no models match vendor",
			models: []capi.Model{
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor},
			},
			vendors:  []string{sweagentd.ModelVendorAnthropic},
			expected: []capi.Model{},
		},
		{
			name: "matches vendor case-insensitively",
			models: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor},
			},
			vendors: []string{"anthropic"},
			expected: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor},
			},
		},
		{
			name: "skips models with nil vendor",
			models: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor},
				{ID: "unknown-model", Vendor: nil},
			},
			vendors: []string{sweagentd.ModelVendorAnthropic},
			expected: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor},
			},
		},
		{
			name: "multi-vendor filters include models from all specified vendors",
			models: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor},
				{ID: "claude-opus-4.5", Vendor: &anthropicVendor},
			},
			vendors: []string{sweagentd.ModelVendorAnthropic, sweagentd.ModelVendorOpenAI},
			expected: []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor},
				{ID: "gpt-5.2-codex", Vendor: &openaiVendor},
				{ID: "claude-opus-4.5", Vendor: &anthropicVendor},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := filterModelsByVendors(tt.models, tt.vendors)
			require.Equal(t, tt.expected, result)
		})
	}
}

func Test_DetermineModel_AgenticAppModelPassthrough(t *testing.T) {
	const ccrAppID int64 = 946600

	tests := []struct {
		name           string
		requestedModel string
		expectedModel  string
		expectedError  error
	}{
		{
			name:           "CCR passthrough with sweagent-capi prefix and bracket options",
			requestedModel: "sweagent-capi:gpt-5.2[ReasoningEffort=medium]",
			expectedModel:  "sweagent-capi:gpt-5.2[ReasoningEffort=medium]",
		},
		{
			name:           "CCR passthrough with bare model and bracket options",
			requestedModel: "gpt-5.1[ReasoningEffort=high]",
			expectedModel:  "gpt-5.1[ReasoningEffort=high]",
		},
		{
			name:           "CCR passthrough with sweagent-capi prefix only",
			requestedModel: "sweagent-capi:claude-sonnet-4.5",
			expectedModel:  "sweagent-capi:claude-sonnet-4.5",
		},
		{
			name:           "CCR with empty model falls through to normal auto selection",
			requestedModel: "",
			expectedModel:  capi.AutoMode,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			obsv := observability.NewNoopExporters()
			ffs := featureflags.NewNoopClient(nil)
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

			capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

			ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-code-review", 0, "copilot-code-review-bot", "commit-login", "commit@email.com")
			provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, ccrApp)

			userDetails := &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasPaidAccess: true,
			}
			twirpClient := newMockTwirpClientWithUserDetails(userDetails)

			s := New(obsv, ffs, store, capiClient, gcf, twirpClient, aq, limiter, exp, nil, "test_name", "test@example.com", nil, provider, nil)

			model, err := s.DetermineModel(ctx, tt.requestedModel, job, ccrAppID, userDetails)
			if tt.expectedError != nil {
				require.ErrorIs(t, err, tt.expectedError)
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.expectedModel, model)
			}
		})
	}
}

func Test_BuildModelSelectionInfo(t *testing.T) {
	anthropicVendor := sweagentd.ModelVendorAnthropic
	openaiVendor := sweagentd.ModelVendorOpenAI

	t.Run("returns nil when feature flag is disabled", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(nil) // flag disabled

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		claudeApp := agenticapptest.NewTestApp(100).WithModelVendors([]string{sweagentd.ModelVendorAnthropic})
		provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp)

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, provider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User"}

		result := s.BuildModelSelectionInfo(ctx, job, 100, nil)
		require.Nil(t, result)
	})

	t.Run("returns nil when agent has no vendors", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentModelSelectionInJobResponse: true,
		})

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		copilotProvider := agenticapptest.NewTestProvider(t) // Copilot returns empty vendors

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, copilotProvider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User"}

		result := s.BuildModelSelectionInfo(ctx, job, 0, nil)
		require.Nil(t, result)
	})

	t.Run("uses cachedModels instead of calling CAPI", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentModelSelectionInJobResponse: true,
		})

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			t.Fatal("CAPI should not be called when cachedModels is provided")
			return nil, nil
		}
		claudeApp := agenticapptest.NewTestApp(100).WithModelVendors([]string{sweagentd.ModelVendorAnthropic})
		provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp)

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, provider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User"}

		cached := []capi.Model{
			{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
		}
		result := s.BuildModelSelectionInfo(ctx, job, 100, cached)
		require.NotNil(t, result)
		require.True(t, result.Enabled)
		require.Equal(t, []string{"claude-sonnet-4.5"}, result.AvailableModels)
	})

	t.Run("excludes policy-disabled models", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentModelSelectionInJobResponse: true,
		})

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		claudeApp := agenticapptest.NewTestApp(100).WithModelVendors([]string{sweagentd.ModelVendorAnthropic})
		provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp)

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, provider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User"}

		cached := []capi.Model{
			{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			{ID: "claude-opus-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateDisabled}},
			{ID: "gpt-5.2-codex", Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
		}
		result := s.BuildModelSelectionInfo(ctx, job, 100, cached)
		require.NotNil(t, result)
		require.Equal(t, []string{"claude-sonnet-4.5"}, result.AvailableModels)
	})

	t.Run("default model uses job model when present and available", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentModelSelectionInJobResponse: true,
		})

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		claudeApp := agenticapptest.NewTestApp(100).WithModelVendors([]string{sweagentd.ModelVendorAnthropic})
		provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp)

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, provider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User", Model: jobs.CapiModelPrefix + "claude-opus-4.5"}

		cached := []capi.Model{
			{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			{ID: "claude-opus-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
		}
		result := s.BuildModelSelectionInfo(ctx, job, 100, cached)
		require.NotNil(t, result)
		require.Equal(t, "claude-opus-4.5", result.DefaultModel)
		require.Equal(t, []string{"claude-sonnet-4.5", "claude-opus-4.5"}, result.AvailableModels)
	})

	t.Run("default model falls back to first entry when job model not available", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentModelSelectionInJobResponse: true,
		})

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		claudeApp := agenticapptest.NewTestApp(100).WithModelVendors([]string{sweagentd.ModelVendorAnthropic})
		provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp)

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, provider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User", Model: jobs.CapiModelPrefix + "gpt-5.2-codex"}

		cached := []capi.Model{
			{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			{ID: "claude-opus-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
		}
		result := s.BuildModelSelectionInfo(ctx, job, 100, cached)
		require.NotNil(t, result)
		require.Equal(t, "claude-sonnet-4.5", result.DefaultModel)
	})

	t.Run("returns nil when all models are policy-disabled", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentModelSelectionInJobResponse: true,
		})

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		claudeApp := agenticapptest.NewTestApp(100).WithModelVendors([]string{sweagentd.ModelVendorAnthropic})
		provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp)

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, provider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User"}

		cached := []capi.Model{
			{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateDisabled}},
		}
		result := s.BuildModelSelectionInfo(ctx, job, 100, cached)
		require.Nil(t, result)
	})

	t.Run("includes vendors in result", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentModelSelectionInJobResponse: true,
		})

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		multiVendorApp := agenticapptest.NewTestApp(300).WithModelVendors([]string{sweagentd.ModelVendorAnthropic, sweagentd.ModelVendorOpenAI})
		provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, multiVendorApp)

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, provider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User"}

		cached := []capi.Model{
			{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			{ID: "gpt-5.2-codex", Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
		}
		result := s.BuildModelSelectionInfo(ctx, job, 300, cached)
		require.NotNil(t, result)
		require.Equal(t, []string{sweagentd.ModelVendorAnthropic, sweagentd.ModelVendorOpenAI}, result.Vendors)
		require.Equal(t, []string{"claude-sonnet-4.5", "gpt-5.2-codex"}, result.AvailableModels)
	})
}

func Test_DetermineModel_CAPIIntegrationID(t *testing.T) {
	individualUserDetails := &copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
		HasPaidAccess: true,
	}
	var mockTwirpClient = newMockTwirpClientWithUserDetails(individualUserDetails)

	anthropicVendor := sweagentd.ModelVendorAnthropic
	openaiVendor := sweagentd.ModelVendorOpenAI

	tests := []struct {
		name                  string
		agentID               int64
		expectedIntegrationID string
	}{
		{
			name:                  "Claude agent passes claude-code-cloud integration ID",
			agentID:               100,
			expectedIntegrationID: "claude-code-cloud",
		},
		{
			name:                  "Codex agent passes codex-cloud integration ID",
			agentID:               200,
			expectedIntegrationID: "codex-cloud",
		},
		{
			name:                  "Copilot agent does not set integration ID",
			agentID:               0,
			expectedIntegrationID: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			obsv := observability.NewNoopExporters()
			ffs := featureflags.NewNoopClient(map[string]bool{
				featureflags.CodingAgentThirdPartyModelVendorFilter: true,
				featureflags.CodingAgentCAPI3pIntegrationID:         true,
			})
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

			capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

			var capturedIntegrationID string
			capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
				capturedIntegrationID = capi.IntegrationIDFromContext(ctx)
				return []capi.Model{
					{ID: capi.ClaudeSonnet46, Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
					{ID: capi.GPT52Codex, Vendor: &openaiVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				}, nil
			}

			claudeApp := agenticapptest.NewTestApp(100).
				WithModelVendors([]string{sweagentd.ModelVendorAnthropic}).
				WithMetadata(map[string]string{sweagentd.MetadataCAPIIntegrationID: "claude-code-cloud"})
			codexApp := agenticapptest.NewTestApp(200).
				WithModelVendors([]string{sweagentd.ModelVendorOpenAI}).
				WithMetadata(map[string]string{sweagentd.MetadataCAPIIntegrationID: "codex-cloud"})
			provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp, codexApp)

			s := New(obsv, ffs, store, capiClient, gcf, mockTwirpClient, aq, limiter, exp, nil, "test_name", "test@example.com", nil, provider, nil)

			_, err := s.DetermineModel(ctx, "", job, tt.agentID, individualUserDetails)
			require.NoError(t, err)

			require.Equal(t, tt.expectedIntegrationID, capturedIntegrationID)
		})
	}
}

func Test_BuildModelSelectionInfo_CAPIIntegrationID(t *testing.T) {
	anthropicVendor := sweagentd.ModelVendorAnthropic

	t.Run("passes integration ID from agent metadata when fetching models", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentModelSelectionInJobResponse: true,
			featureflags.CodingAgentCAPI3pIntegrationID:         true,
		})

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		var capturedIntegrationID string
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			capturedIntegrationID = capi.IntegrationIDFromContext(ctx)
			return []capi.Model{
				{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			}, nil
		}

		claudeApp := agenticapptest.NewTestApp(100).
			WithModelVendors([]string{sweagentd.ModelVendorAnthropic}).
			WithMetadata(map[string]string{sweagentd.MetadataCAPIIntegrationID: "claude-code-cloud"})
		provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp)

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, provider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User"}

		result := s.BuildModelSelectionInfo(ctx, job, 100, nil)
		require.NotNil(t, result)
		require.Equal(t, "claude-code-cloud", capturedIntegrationID)
	})

	t.Run("does not call CAPI when using cached models", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentModelSelectionInJobResponse: true,
		})

		capiClient, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			t.Fatal("CAPI should not be called when cachedModels is provided")
			return nil, nil
		}

		claudeApp := agenticapptest.NewTestApp(100).
			WithModelVendors([]string{sweagentd.ModelVendorAnthropic}).
			WithMetadata(map[string]string{sweagentd.MetadataCAPIIntegrationID: "claude-code-cloud"})
		provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, claudeApp)

		s := New(obsv, ffs, store, capiClient, gcf, githubtwirp.NewNoopClient(), aq, limiter, exp, nil, "test", "test@example.com", nil, provider, nil)
		job := &jobs.Job{ActorID: 1, ActorType: "User"}

		cached := []capi.Model{
			{ID: "claude-sonnet-4.5", Vendor: &anthropicVendor, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
		}
		result := s.BuildModelSelectionInfo(ctx, job, 100, cached)
		require.NotNil(t, result)
	})
}

package jobservice

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	jobExperiments "github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
)

func Test_DetermineModel(t *testing.T) {
	var mockTwirpClientForEnterpriseUser = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	tests := []struct {
		name          string
		variantValue  any
		expectedModel string
	}{
		{
			name:          "Returns ExperimentalModel1 when variant is 1",
			variantValue:  1,
			expectedModel: DefaultModel, // ExperimentalModel1,
		},
		{
			name:          "Returns ExperimentalModel2 when variant is 2",
			variantValue:  2,
			expectedModel: DefaultModel, // ExperimentalModel2,
		},
		{
			name:          "Returns default model when variant is a string",
			variantValue:  "string",
			expectedModel: DefaultModel,
		},
		{
			name:          "Returns default model when variant is nil",
			variantValue:  nil,
			expectedModel: DefaultModel,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			obsv := observability.NewNoopExporters()
			ffs := featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentCanSelectModel: true,
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
			job.Experiments = &jobExperiments.AssignmentExperiments{
				Variations: map[string]any{
					experiments.ModelCompareExperiment: tt.variantValue,
				},
			}
			lm := LabelMetadataForJob(ctx, ffs, job, pr)

			capi, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
			s := New(obsv, ffs, store, capi, gcf, mockTwirpClientForEnterpriseUser, aq, limiter, exp, nil, "test@example.com", nil)

			model := s.DetermineModelWithLabelNames(ctx, job, lm.CopilotLabels)

			require.Equal(t, tt.expectedModel, model)
		})
	}

	t.Run("returns user-selected model if customization using labels is enabled", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCanSelectModel: true,
		})
		pr := eventstest.PullRequest()
		pr.Labels = github.GQLConnection[github.GQLLabel]{
			Nodes: []github.GQLLabel{
				{
					Name: modelLabelPrefix + "gpt-12",
				},
			},
		}
		job := eventstest.Assignment().NewJob(
			jobs.AgentActionFixPRComment,
			jobs.JobActor{
				ID:         eventstest.UserWriter().ID,
				Login:      eventstest.UserWriter().Login,
				TrackingID: "tracking-id",
			},
			pr.HeadRef.Name,
		)

		capi, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, ffs, store, capi, gcf, mockTwirpClientForEnterpriseUser, aq, limiter, exp, nil, "test@example.com", nil)

		lm := LabelMetadataForJob(ctx, ffs, job, pr)
		model := s.DetermineModelWithLabelNames(ctx, job, lm.CopilotLabels)

		require.Equal(t, "gpt-12", model)
	})

	t.Run("returns default model if customization using labels is not enabled", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(nil)
		job := eventstest.Assignment().NewJob(
			jobs.AgentActionFix,
			jobs.JobActor{
				ID:         eventstest.UserWriter().ID,
				Login:      eventstest.UserWriter().Login,
				TrackingID: "tracking-id",
			}, "")

		capi, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, ffs, store, capi, gcf, mockTwirpClientForEnterpriseUser, aq, limiter, exp, nil, "test@example.com", nil)

		issue := eventstest.Issue()
		issue.Labels = github.GQLConnection[github.GQLLabel]{
			Nodes: []github.GQLLabel{
				{
					Name: modelLabelPrefix + "gpt-12",
				},
			},
		}

		lm := LabelMetadataForJob(ctx, ffs, job, issue)
		model := s.DetermineModelWithLabelNames(ctx, job, lm.CopilotLabels)
		require.Equal(t, DefaultModel, model)
	})

	t.Run("uses Daisy when conditions are met", func(t *testing.T) {
		testCases := []struct {
			name          string
			plan          copilotUsersTwirp.CopilotPlan
			policySetting copilotUsersTwirp.Daisy
			paidAccess    bool
			featureFlags  map[string]bool
			expected      string
		}{
			{
				name:       "pro user gets Daisy",
				plan:       copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				paidAccess: true,
				featureFlags: map[string]bool{
					"sweagentd_use_daisy_model_pro_and_pro_plus": true,
				},
				expected: DaisyModel,
			},
			{
				name:       "pro user does not get Daisy when ff disabled",
				plan:       copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				paidAccess: true,
				featureFlags: map[string]bool{
					"sweagentd_use_daisy_model_pro_and_pro_plus": false,
				},
				expected: DefaultModel,
			},
			{
				name: "pro plus user gets Daisy",
				plan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
				featureFlags: map[string]bool{
					"sweagentd_use_daisy_model_pro_and_pro_plus": true,
				},
				expected: DaisyModel,
			},
			{
				name: "pro plus user does not get Daisy when ff disabled",
				plan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
				featureFlags: map[string]bool{
					"sweagentd_use_daisy_model_pro_and_pro_plus": false,
				},
				expected: DefaultModel,
			},
			{
				name:       "free user doesn't get Daisy",
				plan:       copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				paidAccess: false,
				featureFlags: map[string]bool{
					"sweagentd_use_daisy_model_pro_and_pro_plus": true,
				},
				expected: DefaultModel,
			},
			{
				name:          "business user doesn't get Daisy when policy is disabled",
				plan:          copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
				policySetting: copilotUsersTwirp.Daisy_DAISY_DISABLED,
				featureFlags: map[string]bool{
					"sweagentd_use_daisy_model_if_policy_enabled_for_user": true,
				},
				expected: DefaultModel,
			},
			{
				name:          "business user gets Daisy when policy is enabled",
				plan:          copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
				policySetting: copilotUsersTwirp.Daisy_DAISY_ENABLED,
				featureFlags: map[string]bool{
					"sweagentd_use_daisy_model_if_policy_enabled_for_user": true,
				},
				expected: DaisyModel,
			},
			{
				name:          "enterprise user doesn't get Daisy when policy is disabled",
				plan:          copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				policySetting: copilotUsersTwirp.Daisy_DAISY_DISABLED,
				featureFlags: map[string]bool{
					"sweagentd_use_daisy_model_if_policy_enabled_for_user": true,
				},
				expected: DefaultModel,
			},
			{
				name:          "enterprise user gets Daisy when policy is enabled",
				plan:          copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				policySetting: copilotUsersTwirp.Daisy_DAISY_ENABLED,
				featureFlags: map[string]bool{
					"sweagentd_use_daisy_model_if_policy_enabled_for_user": true,
				},
				expected: DaisyModel,
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				ctx := context.Background()
				obsv := observability.NewNoopExporters()
				ffs := featureflags.NewNoopClient(tc.featureFlags)
				mockTwirpClient := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
					HasPaidAccess: tc.paidAccess,
					CopilotPlan:   tc.plan,
					DaisySetting:  tc.policySetting,
				})
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
				s := New(obsv, ffs, store, capi, gcf, mockTwirpClient, aq, limiter, exp, nil, "test@example.com", nil)

				lm := LabelMetadataForJob(ctx, ffs, job, eventstest.Issue())
				model := s.DetermineModelWithLabelNames(ctx, job, lm.CopilotLabels)
				require.Equal(t, tc.expected, model)
			})
		}
	})

	t.Run("doesn't use Daisy when flag is disabled", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			"sweagentd_use_daisy_model_pro_and_pro_plus": false,
		})
		mockTwirpClient := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			HasPaidAccess: true,
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
		})
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
		s := New(obsv, ffs, store, capi, gcf, mockTwirpClient, aq, limiter, exp, nil, "test@example.com", nil)

		lm := LabelMetadataForJob(ctx, ffs, job, eventstest.Issue())
		model := s.DetermineModelWithLabelNames(ctx, job, lm.CopilotLabels)

		// When flag is disabled, should fall back to regular SKU-based logic
		// Pro user should get DefaultModelForBusinessOrPro
		require.Equal(t, DefaultModelForBusinessOrPro, model)
	})

	t.Run("returns candidate model if the sweagentd_use_candidate_model_as_default is enabled", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{
			"sweagentd_use_candidate_model_as_default": true,
		})
		job := eventstest.Assignment().NewJob(
			jobs.AgentActionFix,
			jobs.JobActor{
				ID:         eventstest.UserWriter().ID,
				Login:      eventstest.UserWriter().Login,
				TrackingID: "tracking-id",
			},
			"",
		)

		capi, store, _, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, ffs, store, capi, gcf, mockTwirpClientForEnterpriseUser, aq, limiter, exp, nil, "test@example.com", nil)

		lm := LabelMetadataForJob(ctx, ffs, job, eventstest.Issue())
		model := s.DetermineModelWithLabelNames(ctx, job, lm.CopilotLabels)
		require.Equal(t, CandidateModel, model)
	})

	t.Run("uses SKU to determine default model for Copilot users", func(t *testing.T) {
		var mockTwirpClientForBusinessUser = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
		})

		var mockTwirpClientForBusinessUserWithCfeAccess = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			HasCfeAccess: true,
			CopilotPlan:  copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
		})

		var mockTwirpClientForProPlusUser = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
		})

		var mockTwirpClientForProUser = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
			HasPaidAccess: true,
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
		})

		for name, tt := range map[string]struct {
			client   githubtwirp.ClientInterface
			expected string
		}{
			"enterprise user": {
				client:   mockTwirpClientForEnterpriseUser,
				expected: DefaultModel,
			},
			"business user": {
				client:   mockTwirpClientForBusinessUser,
				expected: DefaultModelForBusinessOrPro,
			},
			"business user with CFE access": {
				client:   mockTwirpClientForBusinessUserWithCfeAccess,
				expected: DefaultModel,
			},
			"pro plus user": {
				client:   mockTwirpClientForProPlusUser,
				expected: DefaultModel,
			},
			"pro user": {
				client:   mockTwirpClientForProUser,
				expected: DefaultModelForBusinessOrPro,
			},
			"error fetching sku": {
				client: func() githubtwirp.ClientInterface {
					client := githubtwirp.NewNoopClient()
					client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
						return nil, errors.New("error fetching copilot user details")
					}
					return client
				}(),
				expected: DefaultModelForBusinessOrPro,
			},
		} {
			t.Run(name, func(t *testing.T) {
				ctx := context.Background()
				obsv := observability.NewNoopExporters()
				ffs := featureflags.NewNoopClient(nil)
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
				s := New(obsv, ffs, store, capi, gcf, tt.client, aq, limiter, exp, nil, "test@example.com", nil)

				lm := LabelMetadataForJob(ctx, ffs, job, eventstest.Issue())
				model := s.DetermineModelWithLabelNames(ctx, job, lm.CopilotLabels)

				require.Equal(t, tt.expected, model)
			})
		}
	})
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

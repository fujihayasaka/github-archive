package jobservice

import (
	"context"
	"maps"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/feature-management-client-go/githubexp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

// paramCapturingExpClient implements exp.ExperimentationClient for testing
// and captures the user params passed to GetAssignment.
type paramCapturingExpClient struct {
	assignmentResult *githubexp.AssignmentResult
	capturedParams   map[string]string
}

func (m *paramCapturingExpClient) ResilientStart(_ context.Context, _ ...githubexp.ResilientStartOption) error {
	return nil
}

func (m *paramCapturingExpClient) GetAssignment(_ context.Context, params map[string]string, _, _ []string) *githubexp.AssignmentResult {
	m.capturedParams = maps.Clone(params)
	return m.assignmentResult
}

// ghTestOrgID is the GitHub org ID used in tests.
const ghTestOrgID = exp.GHOrgID

// msTestOrgID is the Microsoft org ID used in tests.
const msTestOrgID = exp.MSOrgID

// newTestServiceWithSDKClient creates a Service wired with the given paramCapturingExpClient
// for testing ExP SDK assignment behaviour.
func newTestServiceWithSDKClient(t *testing.T, sdkClient *paramCapturingExpClient) *Service {
	t.Helper()
	obsv := observability.NewNoopExporters()
	_, store, _, gcf, legacyExp, aq, limiter := commonServiceDependencies(obsv)
	svc := New(obsv, featureflags.NewNoopClient(nil), store, nil, gcf, nil, aq, limiter, legacyExp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
	return svc.WithExpSDKClient(sdkClient)
}

func TestGetExperimentAssignment_StaffKey(t *testing.T) {
	t.Run("sets staff key for GitHub org member", func(t *testing.T) {
		sdkClient := &paramCapturingExpClient{
			assignmentResult: githubexp.NewAssignmentResult(nil, "", 0),
		}
		svc := newTestServiceWithSDKClient(t, sdkClient)
		userDetails := &copilotUsersTwirp.CopilotUserDetails{
			CopilotOrganizations: []*copilotUsersTwirp.CopilotOrganization{
				{Id: ghTestOrgID},
			},
		}

		svc.GetExperimentAssignment(context.Background(), &jobs.Job{ActorID: 123}, userDetails)

		require.Equal(t, "1", sdkClient.capturedParams[string(exp.StaffKey)])
	})

	t.Run("sets staff key for Microsoft org member", func(t *testing.T) {
		sdkClient := &paramCapturingExpClient{
			assignmentResult: githubexp.NewAssignmentResult(nil, "", 0),
		}
		svc := newTestServiceWithSDKClient(t, sdkClient)
		userDetails := &copilotUsersTwirp.CopilotUserDetails{
			CopilotOrganizations: []*copilotUsersTwirp.CopilotOrganization{
				{Id: msTestOrgID},
			},
		}

		svc.GetExperimentAssignment(context.Background(), &jobs.Job{ActorID: 123}, userDetails)

		require.Equal(t, "1", sdkClient.capturedParams[string(exp.StaffKey)])
	})

	t.Run("sets staff key for Microsoft Copilot org member", func(t *testing.T) {
		sdkClient := &paramCapturingExpClient{
			assignmentResult: githubexp.NewAssignmentResult(nil, "", 0),
		}
		svc := newTestServiceWithSDKClient(t, sdkClient)
		userDetails := &copilotUsersTwirp.CopilotUserDetails{
			CopilotOrganizations: []*copilotUsersTwirp.CopilotOrganization{
				{Id: exp.MSCopilotOrgID},
			},
		}

		svc.GetExperimentAssignment(context.Background(), &jobs.Job{ActorID: 123}, userDetails)

		require.Equal(t, "1", sdkClient.capturedParams[string(exp.StaffKey)])
	})

	t.Run("sets staff key for ArgosGH org member", func(t *testing.T) {
		sdkClient := &paramCapturingExpClient{
			assignmentResult: githubexp.NewAssignmentResult(nil, "", 0),
		}
		svc := newTestServiceWithSDKClient(t, sdkClient)
		userDetails := &copilotUsersTwirp.CopilotUserDetails{
			CopilotOrganizations: []*copilotUsersTwirp.CopilotOrganization{
				{Id: exp.ArgosGHOrgID},
			},
		}

		svc.GetExperimentAssignment(context.Background(), &jobs.Job{ActorID: 123}, userDetails)

		require.Equal(t, "1", sdkClient.capturedParams[string(exp.StaffKey)])
	})

	t.Run("sets staff key to 0 for non-staff user", func(t *testing.T) {
		sdkClient := &paramCapturingExpClient{
			assignmentResult: githubexp.NewAssignmentResult(nil, "", 0),
		}
		svc := newTestServiceWithSDKClient(t, sdkClient)
		userDetails := &copilotUsersTwirp.CopilotUserDetails{
			CopilotOrganizations: []*copilotUsersTwirp.CopilotOrganization{
				{Id: 99999},
			},
		}

		svc.GetExperimentAssignment(context.Background(), &jobs.Job{ActorID: 123}, userDetails)

		require.Equal(t, "0", sdkClient.capturedParams[string(exp.StaffKey)])
	})

	t.Run("omits staff key when userDetails is nil", func(t *testing.T) {
		sdkClient := &paramCapturingExpClient{
			assignmentResult: githubexp.NewAssignmentResult(nil, "", 0),
		}
		svc := newTestServiceWithSDKClient(t, sdkClient)

		svc.GetExperimentAssignment(context.Background(), &jobs.Job{ActorID: 123}, nil)

		_, hasStaffKey := sdkClient.capturedParams[string(exp.StaffKey)]
		require.False(t, hasStaffKey, "staff key should not be set when userDetails is nil")
	})
}

func TestGetExperimentAssignment_CopilotPlanKey(t *testing.T) {
	tests := []struct {
		name         string
		userDetails  *copilotUsersTwirp.CopilotUserDetails
		expectedPlan string
		expectKey    bool
	}{
		{
			name: "sends COPILOT_PLAN_INDIVIDUAL_FREE for free plan user",
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:      copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasFreeAccess:    true,
				HasLimitedAccess: true,
			},
			expectedPlan: "COPILOT_PLAN_INDIVIDUAL_FREE",
			expectKey:    true,
		},
		{
			name: "sends COPILOT_PLAN_INDIVIDUAL for paid individual user",
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasPaidAccess: true,
			},
			expectedPlan: "COPILOT_PLAN_INDIVIDUAL",
			expectKey:    true,
		},
		{
			name: "sends COPILOT_PLAN_INDIVIDUAL_PRO_PLUS for pro plus user",
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
				HasPaidAccess: true,
			},
			expectedPlan: "COPILOT_PLAN_INDIVIDUAL_PRO_PLUS",
			expectKey:    true,
		},
		{
			name: "sends COPILOT_PLAN_BUSINESS for business user",
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
				HasPaidAccess: true,
			},
			expectedPlan: "COPILOT_PLAN_BUSINESS",
			expectKey:    true,
		},
		{
			name: "sends COPILOT_PLAN_ENTERPRISE for enterprise user",
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				HasPaidAccess: true,
			},
			expectedPlan: "COPILOT_PLAN_ENTERPRISE",
			expectKey:    true,
		},
		{
			name:        "omits plan key when userDetails is nil",
			userDetails: nil,
			expectKey:   false,
		},
		{
			name: "omits plan key for unknown plan and does not break assignment",
			userDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan(9999),
			},
			expectKey: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sdkClient := &paramCapturingExpClient{
				assignmentResult: githubexp.NewAssignmentResult(nil, "", 0),
			}
			svc := newTestServiceWithSDKClient(t, sdkClient)

			assignment := svc.GetExperimentAssignment(context.Background(), &jobs.Job{ActorID: 123}, tt.userDetails)
			require.NotNil(t, assignment, "assignment should always be returned")

			planValue, hasPlanKey := sdkClient.capturedParams[string(exp.CopilotPlanKey)]
			if tt.expectKey {
				require.True(t, hasPlanKey, "plan key should be present")
				require.Equal(t, tt.expectedPlan, planValue)
			} else {
				require.False(t, hasPlanKey, "plan key should not be present")
			}
		})
	}
}

package githubtwirp

import (
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCopilotPlanFromUser(t *testing.T) {
	t.Run("individual with free and limited access returns free plan", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan:      copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			HasFreeAccess:    true,
			HasLimitedAccess: true,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForIndividualFree, plan)
	})

	t.Run("individual with free access but not limited returns individual", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan:      copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			HasFreeAccess:    true,
			HasLimitedAccess: false,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForIndividual, plan)
	})

	t.Run("individual with paid access returns individual", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			HasPaidAccess: true,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForIndividual, plan)
	})

	t.Run("individual with no special access returns trial", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForIndividualTrial, plan)
	})

	t.Run("individual pro returns pro plus", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForIndividualProPlus, plan)
	})

	t.Run("individual max returns max", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_MAX,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForIndividualMax, plan)
	})

	t.Run("individual edu returns edu", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_EDU,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForIndividualEdu, plan)
	})

	t.Run("business without CFE access returns business", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan:  copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			HasCfeAccess: false,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForBusiness, plan)
	})

	t.Run("business with CFE access returns enterprise", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan:  copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			HasCfeAccess: true,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForEnterprise, plan)
	})

	t.Run("enterprise plan returns enterprise", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotForEnterprise, plan)
	})

	t.Run("invalid plan returns invalid", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INVALID,
		}

		plan, err := CopilotPlanFromUser(details)
		require.NoError(t, err)
		assert.Equal(t, CopilotPlanInvalid, plan)
	})

	t.Run("unknown plan returns error", func(t *testing.T) {
		details := &copilotUsersTwirp.CopilotUserDetails{
			CopilotPlan: copilotUsersTwirp.CopilotPlan(9999),
		}

		plan, err := CopilotPlanFromUser(details)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "unknown copilot user plan")
		assert.Equal(t, CopilotPlanInvalid, plan)
	})
}

func TestCopilotPlan_IsPaidIndividual(t *testing.T) {
	tests := []struct {
		plan     CopilotPlan
		expected bool
	}{
		{CopilotForIndividual, true},
		{CopilotForIndividualProPlus, true},
		{CopilotForIndividualMax, true},
		{CopilotForIndividualEdu, true},
		{CopilotForIndividualFree, false},
		{CopilotForIndividualTrial, false},
		{CopilotForBusiness, false},
		{CopilotForEnterprise, false},
		{CopilotPlanInvalid, false},
	}

	for _, tt := range tests {
		t.Run(string(tt.plan), func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.plan.IsPaidIndividual())
		})
	}
}

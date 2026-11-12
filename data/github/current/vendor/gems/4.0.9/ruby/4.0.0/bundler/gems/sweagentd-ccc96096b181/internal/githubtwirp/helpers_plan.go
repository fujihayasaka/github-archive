package githubtwirp

import (
	"context"
	"fmt"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
)

// Based on code from github/copilot-api
// Ref: https://github.com/github/copilot-api/blob/e00afebb4fa32f2fbe1455b63bfad8f4f5c969b2/pkg/rest/requestctx/requestctx.go
// Ref: https://github.com/github/copilot-api/blob/e00afebb4fa32f2fbe1455b63bfad8f4f5c969b2/pkg/dotcom/twirp.go

// CopilotPlan is the plan that the user is on. This is different from SKU,
// and is just the overarching plan (CfI, CfB, etc). The value is an enum
// that we get back from the copilot-twirp API.
type CopilotPlan string

var (
	// CopilotForIndividual denotes that the user is on the individual pro plan.
	CopilotForIndividual CopilotPlan = "COPILOT_PLAN_INDIVIDUAL"
	// CopilotForIndividualFree denotes that the user is on the individual free plan.
	CopilotForIndividualFree CopilotPlan = "COPILOT_PLAN_INDIVIDUAL_FREE"
	// CopilotForIndividualTrial denotes that the user is on the individual trial plan.
	CopilotForIndividualTrial CopilotPlan = "COPILOT_PLAN_INDIVIDUAL_TRIAL"
	// CopilotForIndividualProPlus denotes that the user is on the individual pro plus plan.
	CopilotForIndividualProPlus CopilotPlan = "COPILOT_PLAN_INDIVIDUAL_PRO_PLUS"
	// CopilotForBusiness denotes that the user is on the business plan.
	CopilotForBusiness CopilotPlan = "COPILOT_PLAN_BUSINESS"
	// CopilotForEnterprise denotes that the user is on the enterprise plan.
	CopilotForEnterprise CopilotPlan = "COPILOT_PLAN_ENTERPRISE"
	// CopilotPlanInvalid denotes that the user's plan is invalid.
	CopilotPlanInvalid CopilotPlan = "COPILOT_PLAN_INVALID"
)

func (c CopilotPlan) String() string {
	return string(c)
}

func (c CopilotPlan) IsPaidIndividual() bool {
	return c == CopilotForIndividual || c == CopilotForIndividualProPlus
}

func GetCopilotPlan(ctx context.Context, twirpClient ClientInterface, userID int64) (CopilotPlan, error) {
	userDetails, err := twirpClient.GetCopilotUserDetails(ctx, userID)
	if err != nil {
		return CopilotPlanInvalid, fmt.Errorf("failed to get user details: %w", err)
	}

	if userDetails == nil {
		return CopilotPlanInvalid, fmt.Errorf("user details are nil for user %d", userID)
	}

	return CopilotPlanFromUser(userDetails)
}

// CopilotPlanFromUser returns the CopilotPlan for a given user response from the copilot-twirp API.
func CopilotPlanFromUser(userDetails *copilotUsersTwirp.CopilotUserDetails) (CopilotPlan, error) {
	p := userDetails.CopilotPlan
	hasCfeAccess := userDetails.HasCfeAccess
	hasFreeAccess := userDetails.HasFreeAccess
	hasPaidAccess := userDetails.HasPaidAccess
	hasLimitedAccess := userDetails.HasLimitedAccess

	switch p {
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL:
		// "Free" users have both free and limited access
		if hasFreeAccess && hasLimitedAccess {
			return CopilotForIndividualFree, nil
		}
		// Users with free but not limited access are treated as "Individual" (aka Pro)
		// For example, this is the case for users who have "Education Free" access.
		if hasFreeAccess && !hasLimitedAccess {
			return CopilotForIndividual, nil
		}
		if hasPaidAccess {
			return CopilotForIndividual, nil
		}
		return CopilotForIndividualTrial, nil
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO:
		return CopilotForIndividualProPlus, nil
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS:
		if hasCfeAccess {
			return CopilotForEnterprise, nil
		}
		return CopilotForBusiness, nil
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE:
		return CopilotForEnterprise, nil
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INVALID:
		return CopilotPlanInvalid, nil
	default:
		return CopilotPlanInvalid, fmt.Errorf("unknown copilot user plan: %v", p)
	}
}

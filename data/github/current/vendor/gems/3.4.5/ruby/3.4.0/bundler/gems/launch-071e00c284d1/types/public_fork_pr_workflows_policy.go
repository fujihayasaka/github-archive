package types

import (
	"github.com/pkg/errors"
)

// PublicForkPRWorkflowsPolicy determines under what conditions public fork PR workflows run
// See https://github.com/github/github/blob/master/lib/configurable/default_workflow_permissions.rb
type PublicForkPRWorkflowsPolicy int

const (
	// ForkPRWorkflowsInvalid means policy is not valid, wf should not run.
	PublicForkPRWorkflowsInvalidPolicy PublicForkPRWorkflowsPolicy = iota

	// PublicForkPRWorkflowsRunWorkflows means workflows should run
	PublicForkPRWorkflowsRunWorkflows

	// ForkPRWorkflowsRunWithTokensAndSecrets means workflows should run with variables
	PublicForkPRWorkflowsRunWithVariables
)

var publicPolicyEnumMap = map[string]PublicForkPRWorkflowsPolicy{
	"INVALID":            PublicForkPRWorkflowsInvalidPolicy,
	"RUN_WORKFLOWS":      PublicForkPRWorkflowsRunWorkflows,
	"RUN_WITH_VARIABLES": PublicForkPRWorkflowsRunWithVariables,
}

var publicReversePolicyEnumMap = map[PublicForkPRWorkflowsPolicy]string{
	PublicForkPRWorkflowsInvalidPolicy:    "INVALID",
	PublicForkPRWorkflowsRunWorkflows:     "RUN_WORKFLOWS",
	PublicForkPRWorkflowsRunWithVariables: "RUN_WITH_VARIABLES",
}

func (p PublicForkPRWorkflowsPolicy) String() string {
	if v, ok := publicReversePolicyEnumMap[p]; ok {
		return v
	}
	return ""
}

func (p *PublicForkPRWorkflowsPolicy) UnmarshalText(text []byte) error {
	v, ok := publicPolicyEnumMap[string(text)]

	if !ok {
		return errors.Errorf("Unknown publicForkPRWorkflowsPolicy value: %q", text)
	}

	*p = v
	return nil
}

func (p PublicForkPRWorkflowsPolicy) ShouldSendVariables() bool {
	return p == PublicForkPRWorkflowsRunWithVariables
}

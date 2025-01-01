package types

import (
	"github.com/pkg/errors"
)

// ForkPRWorkflowsPolicy determines under what conditions fork PR workflows run
// See https://github.com/github/github/blob/master/lib/configurable/default_workflow_permissions.rb
type ForkPRWorkflowsPolicy int

const (
	// ForkPRWorkflowsDisabled means fork PR workflows should not run
	ForkPRWorkflowsDisabled ForkPRWorkflowsPolicy = iota

	// ForkPRWorkflowsRunWorkflows means workflows should run with read-only tokens and no secrets
	ForkPRWorkflowsRunWorkflows

	// ForkPRWorkflowsRunWithTokens means workflows should run with write tokens and no secrets
	ForkPRWorkflowsRunWithTokens

	// ForkPRWorkflowsRunWithSecrets means workflows should run with read-only tokens and secrets
	ForkPRWorkflowsRunWithSecrets

	// ForkPRWorkflowsRunWithTokensAndSecrets means workflows should run with write tokens and secrets
	ForkPRWorkflowsRunWithTokensAndSecrets
)

var policyEnumMap = map[string]ForkPRWorkflowsPolicy{
	"DISABLED":                    ForkPRWorkflowsDisabled,
	"RUN_WORKFLOWS":               ForkPRWorkflowsRunWorkflows,
	"RUN_WITH_TOKENS":             ForkPRWorkflowsRunWithTokens,
	"RUN_WITH_SECRETS":            ForkPRWorkflowsRunWithSecrets,
	"RUN_WITH_TOKENS_AND_SECRETS": ForkPRWorkflowsRunWithTokensAndSecrets,
}

var reversePolicyEnumMap = map[ForkPRWorkflowsPolicy]string{
	ForkPRWorkflowsDisabled:                "DISABLED",
	ForkPRWorkflowsRunWorkflows:            "RUN_WORKFLOWS",
	ForkPRWorkflowsRunWithTokens:           "RUN_WITH_TOKENS",
	ForkPRWorkflowsRunWithSecrets:          "RUN_WITH_SECRETS",
	ForkPRWorkflowsRunWithTokensAndSecrets: "RUN_WITH_TOKENS_AND_SECRETS",
}

func (p ForkPRWorkflowsPolicy) String() string {
	if v, ok := reversePolicyEnumMap[p]; ok {
		return v
	}
	return ""
}

func (p *ForkPRWorkflowsPolicy) UnmarshalText(text []byte) error {
	v, ok := policyEnumMap[string(text)]

	if !ok {
		return errors.Errorf("Unknown forkPRWorkflowsPolicy value: %q", text)
	}

	*p = v
	return nil
}

func (p ForkPRWorkflowsPolicy) ShouldRun() bool {
	return p != ForkPRWorkflowsDisabled
}

func (p ForkPRWorkflowsPolicy) ShouldSendWriteToken() bool {
	return p == ForkPRWorkflowsRunWithTokens || p == ForkPRWorkflowsRunWithTokensAndSecrets
}

func (p ForkPRWorkflowsPolicy) ShouldSendSecrets() bool {
	// this sends variables as well for private forks for now
	return p == ForkPRWorkflowsRunWithSecrets || p == ForkPRWorkflowsRunWithTokensAndSecrets
}

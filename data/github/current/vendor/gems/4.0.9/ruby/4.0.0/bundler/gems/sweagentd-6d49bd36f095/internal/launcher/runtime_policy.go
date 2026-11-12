package launcher

import (
	"context"
	"fmt"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
)

// runtimePolicyRules is a map of policy rule names to their corresponding evaluation functions.
//
// To add a new policy rule:
//   - Define a new function that matches the runtimePolicyRule signature to evaluate the rule.
//   - Add an entry to this map with a unique name for the rule and the function you defined.
//
// To avoid naming conflicts, rule names will be prefixed like the following when sent to the runtime as flags...
//
//	policy:<rule_name>
//
// ...where <rule_name> is the key used in this map.
var runtimePolicyRules = map[string]runtimePolicyRule{
	"disable_triggered_cca_code_change_tools":     ruleDisableTriggeredCCACodeChangeTools,
	"disable_triggered_cca_runtime_publish_tools": ruleDisableTriggeredCCARuntimePublishTools,
	"disable_cca_triggering_mcp_tools":            ruleDisableCCATriggeringMCPTools,
	"granular_mcp_toolsets":                       ruleGranularMCPToolsets,
}

// runtimePolicyRule defines the signature for a function that evaluates a specific policy rule.
type runtimePolicyRule func(ctx context.Context, ffClient featureflags.Client, opts *LaunchAgentOpts) (bool, error)

// runtimePolicyFlagPrefix is the prefix added when converting policy outcomes to flags.
const runtimePolicyFlagPrefix = "policy"

// RuntimePolicyEvaluator is responsible for evaluating all defined policy rules and returning their outcomes.
type RuntimePolicyEvaluator struct {
	ffClient featureflags.Client
}

// Evaluate evaluates all defined policy rules and returns a map of rule names to their outcomes.
func (pe *RuntimePolicyEvaluator) Evaluate(ctx context.Context, opts *LaunchAgentOpts) (map[string]bool, error) {
	result := make(map[string]bool, len(runtimePolicyRules))
	for name, rule := range runtimePolicyRules {
		outcome, err := rule(ctx, pe.ffClient, opts)
		if err != nil {
			return nil, goerrors.Errorf("failed to evaluate policy rule %s: %w", name, err)
		}
		result[name] = outcome
	}
	return result, nil
}

// EvaluateAsFlags is a utility function that returns a prefixed list of enabled policy rules. Keeping this separate
// from Evaluate allows us to have evaluate return outcomes like "unset" over time that can then be interpreted here.
func (pe *RuntimePolicyEvaluator) EvaluateAsFlags(ctx context.Context, opts *LaunchAgentOpts) ([]string, error) {
	outcomes, err := pe.Evaluate(ctx, opts)
	if err != nil {
		return nil, err
	}
	var flags []string
	for name, enabled := range outcomes {
		if enabled {
			flags = append(flags, fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, name))
		}
	}
	return flags, nil
}

// ruleDisableTriggeredCCACodeChangeTools disables GitHub MCP code-change tools for triggered CCA jobs.
// This is meant for automation/triggered call paths only, not the normal user-invoked flow.
func ruleDisableTriggeredCCACodeChangeTools(ctx context.Context, ffClient featureflags.Client, opts *LaunchAgentOpts) (bool, error) {
	return opts.IsTriggered && ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTriggersDisallowCodeChangeTools, opts), nil
}

// ruleDisableTriggeredCCARuntimePublishTools disables runtime-owned publish tools for triggered CCA jobs.
// This is meant for automation/triggered call paths only, not the normal user-invoked flow.
func ruleDisableTriggeredCCARuntimePublishTools(ctx context.Context, ffClient featureflags.Client, opts *LaunchAgentOpts) (bool, error) {
	return opts.IsTriggered && ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTriggersDisallowRuntimePublishTools, opts), nil
}

// ruleDisableCCATriggeringMCPTools evaluates the policy rule for disabling CCA triggering MCP tools.
func ruleDisableCCATriggeringMCPTools(ctx context.Context, ffClient featureflags.Client, opts *LaunchAgentOpts) (bool, error) {
	if !ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCCATriggeringMCPToolsEnabled, opts) ||
		ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCCATriggeringMCPToolsDisallow, opts) {
		return true, nil
	}
	return false, nil
}

// ruleGranularMCPToolsets replaces coarse issue and pull request tools with granular tools for automations.
func ruleGranularMCPToolsets(ctx context.Context, ffClient featureflags.Client, opts *LaunchAgentOpts) (bool, error) {
	if opts.IsTriggered && ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentGranularMCPToolsets, opts) {
		return true, nil
	}
	return false, nil
}

// Package environmentfeatures provides types for configuring agent features such as
// copilot setup steps, branch creation, and pull request creation.
package environmentfeatures

import "slices"

var (
	// Unset defines a Features object where no features were configured.
	// Use IsUnset() to check whether features were explicitly specified.
	Unset = Features{}

	// Default includes Features with the standard defaults: copilot-setup-steps
	// and pull-request enabled with empty (default) configurations.
	Default = Features{
		isSet:             true,
		CopilotSetupSteps: &CopilotSetupSteps{},
		PullRequest:       &PullRequest{},
	}
)

// FeaturesProvider is satisfied by CustomAgent implementations that
// expose resolved feature sets.
type FeaturesProvider interface {
	Features() Features
}

// CopilotSetupSteps describes the copilot-setup-steps feature configuration.
type CopilotSetupSteps struct {
	// Skip indicates that copilot-setup-steps should not be applied
	// even though the feature is configured. Defaults to false.
	Skip bool

	// Exclude is a list of customization property names to ignore when
	// applying copilot-setup-steps (e.g. "steps", "runs-on", "permissions").
	// Mutually exclusive with Only. An error will be thrown if both are used.
	Exclude []string

	// Only is an allow-list of customization property names to honor when
	// applying copilot-setup-steps. When non-empty, every property not listed
	// here is ignored, including any new properties added to the service's
	// known set in the future. Mutually exclusive with Exclude.
	// An error will be thrown if both are used.
	Only []string
}

// Branch describes the branch feature configuration.
type Branch struct {
	// Name is the name of the branch to create for the job.
	Name string
	// BaseRef is the base ref that the branch is created from.
	BaseRef string
}

// PullRequest describes the pull request feature configuration.
type PullRequest struct {
	// BaseRef is the base branch that the pull request targets.
	BaseRef string
	// HeadRef is the branch that will be used for the PR.
	HeadRef string
}

// Features describes the features configured for a custom agent or job request.
// A nil CopilotSetupSteps, Branch, or PullRequest means that feature is disabled.
type Features struct {
	// isSet is true when the features field was explicitly present
	// in the custom agent YAML config, even if all sub-features are nil
	// (e.g. "features: {}").
	isSet bool

	// CopilotSetupSteps configures copilot setup steps. Disabled when nil.
	CopilotSetupSteps *CopilotSetupSteps

	// Branch, when non-nil, configures branch creation for the job.
	Branch *Branch

	// PullRequest, when non-nil, configures pull request creation for the job.
	PullRequest *PullRequest
}

// New creates a Features marked as explicitly specified.
func New() Features {
	return Features{isSet: true}
}

// IsUnset returns true if no features were configured — neither the specified
// flag is set nor any sub-feature is non-nil.
func (f Features) IsUnset() bool {
	return !f.isSet && f.CopilotSetupSteps == nil && f.Branch == nil && f.PullRequest == nil
}

// CopilotSetupStepsEnabled returns whether copilot setup steps should be applied.
// Returns true by default; only returns false when CopilotSetupSteps is explicitly
// configured with Skip set to true.
func (f Features) CopilotSetupStepsEnabled() bool {
	return f.CopilotSetupSteps == nil || !f.CopilotSetupSteps.Skip
}

// CopilotSetupStepsPropertyExcluded returns whether a specific customization
// property should be excluded when applying copilot-setup-steps.
func (f Features) CopilotSetupStepsPropertyExcluded(propName string) bool {
	if f.CopilotSetupSteps == nil {
		return false
	}
	return slices.Contains(f.CopilotSetupSteps.Exclude, propName)
}

// CopilotSetupStepsHasOnly returns whether an Only allow-list is configured
// for copilot-setup-steps. When true, only properties listed in Only should be
// honored; all others must be ignored.
func (f Features) CopilotSetupStepsHasOnly() bool {
	return f.CopilotSetupSteps != nil && len(f.CopilotSetupSteps.Only) > 0
}

// CopilotSetupStepsPropertyAllowed returns whether a specific customization
// property is allowed by the Only allow-list. Returns true when no Only list
// is configured (allow-all default); otherwise returns true only when the
// property is explicitly listed.
func (f Features) CopilotSetupStepsPropertyAllowed(propName string) bool {
	if !f.CopilotSetupStepsHasOnly() {
		return true
	}
	return slices.Contains(f.CopilotSetupSteps.Only, propName)
}

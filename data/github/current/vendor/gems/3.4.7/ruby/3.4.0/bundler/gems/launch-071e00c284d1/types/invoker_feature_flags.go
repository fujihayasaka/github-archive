package types

// InvokerFeatureFlags are feature flags at the repository level
type InvokerFeatureFlags struct {
	IsActionsEligible bool
	LaunchLabEnabled  bool
}

// WorkflowFeatureFlags are feature flags affecting features within a workflow
type WorkflowFeatureFlags struct {
	ConfigurationVariablesEnabled              bool
	SizeRestrictedVarCountEnabled              bool
	IncreasedMaxWorkflowFilesReferencedEnabled bool
	CustomImagesPolicyEnforced                 bool
	WorkflowApprovalsUsePRAuthorEnabled        bool
	SkipParserErrorsEnabled                    bool
}

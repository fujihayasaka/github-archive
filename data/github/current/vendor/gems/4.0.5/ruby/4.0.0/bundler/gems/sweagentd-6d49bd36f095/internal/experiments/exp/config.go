package exp

// FilterID represents a parameter key serialized into userParams for use as a
// randomization unit or audience filter with the ExP SDK.
type FilterID string

// Randomization unit keys identify the unit being randomly assigned to an
// experiment arm.
const (
	// CopilotTrackingIDKey randomizes by the actor's Copilot analytics tracking ID (user-level).
	CopilotTrackingIDKey FilterID = "copilottrackingid"
	// RepositoryIDKey randomizes by repository ID.
	RepositoryIDKey FilterID = "github_core_repositoryid"
	// OrganizationIDKey randomizes by organization ID.
	// Note: this assignment unit does not exist yet in the new workspace.
	OrganizationIDKey FilterID = "github_core_organizationid"
)

// Audience filter keys segment traffic for experiment targeting.
const (
	// ExtensionNameKey identifies the product/extension making the request.
	ExtensionNameKey FilterID = "extensionname"
	// StaffKey indicates whether the actor is a GitHub or Microsoft staff member.
	StaffKey FilterID = "github_core_isghormsftstaff"
	// CLIVersionKey identifies the version of the Copilot CLI making the request.
	CLIVersionKey FilterID = "github_copilotcli_cliversion"
	// CopilotPlanKey identifies the actor's Copilot plan (e.g. COPILOT_PLAN_INDIVIDUAL).
	CopilotPlanKey FilterID = "github_copilot_plan"
)

// Staff organization IDs used to identify GitHub employees.
const (
	ArgosGHOrgID   uint64 = 217663494 // https://admin.github.com/stafftools/users/argos-gh
	GHOrgID        uint64 = 9919      // https://admin.github.com/stafftools/users/github
	MSCopilotOrgID uint64 = 113467149 // https://admin.github.com/stafftools/users/ms-copilot
	MSOrgID        uint64 = 6154722   // https://admin.github.com/stafftools/users/microsoft
)

// Extension name values used with ExtensionNameKey.
const (
	// ExtensionNameCodingAgent is the extension name for Copilot Coding Agent requests.
	ExtensionNameCodingAgent = "CopilotCodingAgent"
	// ExtensionNameAgenticMemory is the extension name for Agentic Memory requests.
	ExtensionNameAgenticMemory = "AgenticMemory"
	// ExtensionNameCopilotCLI is the extension name for Copilot CLI requests.
	ExtensionNameCopilotCLI = "CopilotCLI"
)

// Flag represents an experiment feature flag with an optional namespace.
// Feature variable keys returned by the ExP SDK are prefixed with "/" when
// flattening JSON payloads. Keys are "/<namespace>/flag_name". The default
// namespace in our ExP workspace is "default", so keys are "/default/flag_name"
// unless a custom namespace is specified.
type Flag struct {
	// Namespace is the ExP experiment namespace. When empty, "default" is used.
	Namespace string
	// Name is the feature variable name within the experiment.
	Name string
}

// Experiment groups related feature flags under descriptive string keys.
type Experiment map[string]Flag

// Experiments.
var (
	// CopilotCodingAgentAAExperiment is the A/A test experiment for Copilot Coding Agent.
	CopilotCodingAgentAAExperiment = Experiment{
		"control": {Name: "cca_aa_test"},
	}
	// CopilotCodingAgentAutoModel is the auto model selection experiment for Copilot Coding Agent.
	CopilotCodingAgentAutoModel = Experiment{
		"control": {Name: "cca_auto_model_control"},
		"var1":    {Name: "cca_auto_model_var1"},
		"var2":    {Name: "cca_auto_model_var2"},
	}

	// MemoryExperiment controls the memory enablement A/B experiment.
	MemoryExperiment = Flag{Namespace: "default", Name: "memory_enabled"}

	// CCAMemoryLimitExperiment controls the number of memories included in the
	// CCA prompt context. The flag value is an integer representing the maximum
	// number of memories to return from the /prompt endpoint.
	CCAMemoryLimitExperiment = Flag{Namespace: "default", Name: "cca_memory_limit"}
)

// IsActorStaff reports whether any of the given organization IDs belong to a
// GitHub staff organization (GitHub, Microsoft, or Microsoft Copilot).
func IsActorStaff(orgIDs []uint64) bool {
	for _, id := range orgIDs {
		switch id {
		case ArgosGHOrgID, GHOrgID, MSCopilotOrgID, MSOrgID:
			return true
		}
	}
	return false
}

// FlagKey returns the feature variable key for use with AssignmentResult
// getters (GetString, GetBool, GetInt, GetFloat64). Returns
// "/default/flag_name" when no namespace is set, or "/<namespace>/flag_name"
// when a custom namespace is configured.
func FlagKey(flag Flag) string {
	ns := flag.Namespace
	if ns == "" {
		ns = "default"
	}
	return "/" + ns + "/" + flag.Name
}

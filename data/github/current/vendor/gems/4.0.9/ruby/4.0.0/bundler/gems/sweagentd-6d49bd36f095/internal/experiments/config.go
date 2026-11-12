package experiments

const (
	// AAExperiment and related constants define experiment identifiers used by the experiments package.
	AAExperiment = "ghpad_aa"
	// AutoModelExperiment is the identifier for the auto mode model comparison experiment.
	AutoModelExperiment = "auto_model_experiment"
	// BlackbirdAblation is the identifier for the blackbird ablation experiment.
	BlackbirdAblation = "blackbird_ablation"
	// BlackbirdTool is the identifier for the blackbird tool use experiment.
	BlackbirdTool = "blackbird_tool"
	// ModelCompareExperiment is the identifier for the model comparison experiment.
	ModelCompareExperiment = "padawan_exp_oswe"
	// SearchAgentExperiment is the identifier for the agentic search tool experiment.
	SearchAgentExperiment = "search_agent_experiment"
	// MemoryExperiment is the identifier for the memory A/B experiment.
	MemoryExperiment = "memory_experiment"
)

// RandomizationUnitType defines how an experiment is randomized.
type RandomizationUnitType int

const (
	// RandomizeByPRID randomizes by pull request ID (default).
	RandomizeByPRID RandomizationUnitType = iota
	// RandomizeByTrackingID randomizes by the actor's Copilot analytics tracking ID (user-level).
	RandomizeByTrackingID
	// RandomizeByRepoID randomizes by repository ID (repo-level).
	RandomizeByRepoID
)

// experimentRandomizationUnits maps experiment names to their randomization unit type.
// Experiments not listed here default to RandomizeByPRID.
var experimentRandomizationUnits = map[string]RandomizationUnitType{
	AutoModelExperiment: RandomizeByTrackingID,
}

// GetRandomizationUnitType returns the randomization unit type for the given experiment.
// If the experiment is not configured, it defaults to RandomizeByPRID.
func GetRandomizationUnitType(experimentName string) RandomizationUnitType {
	if unitType, ok := experimentRandomizationUnits[experimentName]; ok {
		return unitType
	}
	return RandomizeByPRID
}

// AllExperiments are the set of all experiments to look up
var AllExperiments = []string{
	AAExperiment,
	AutoModelExperiment,
	BlackbirdAblation,
	BlackbirdTool,
	MemoryExperiment,
	ModelCompareExperiment,
	SearchAgentExperiment,
}

package experiments

const (
	// AAExperiment and related constants define experiment identifiers used by the experiments package.
	AAExperiment = "ghpad_aa"
	// ModelCompareExperiment is the identifier for the model comparison experiment.
	ModelCompareExperiment = "padawan_exp_oswe"
	// BlackbirdAblation is the identifier for the blackbird ablation experiment.
	BlackbirdAblation = "blackbird_ablation"
	// BlackbirdTool is the identifier for the blackbird tool use experiment.
	BlackbirdTool = "blackbird_tool"
	// SearchAgentExperiment is the identifier for the agentic search tool experiment.
	SearchAgentExperiment = "search_agent_experiment"
)

// AllExperiments are the set of all experiments to look up
var AllExperiments = []string{
	AAExperiment,
	ModelCompareExperiment,
	BlackbirdAblation,
	BlackbirdTool,
	SearchAgentExperiment,
}

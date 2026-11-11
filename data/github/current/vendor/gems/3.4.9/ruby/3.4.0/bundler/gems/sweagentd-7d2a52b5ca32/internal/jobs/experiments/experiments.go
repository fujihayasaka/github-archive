package experiments

// AssignmentExperiments holds experiment assignment details for a job. It is
// used to store experiment variations and context for a job that is part of an
// experiment.
// Experiments are persisted on the assignment and copied to jobs created from
// that assignment to ensure consistency across jobs for the same assignment.
type AssignmentExperiments struct {
	Variations        map[string]any `json:"variations"`
	AssignmentContext string         `json:"assignment_context"`

	// Deprecated but needed for backwards compatibility with old PRs
	Features         []string                      `json:"features,omitempty"`
	Flights          map[string]string             `json:"flights,omitempty"`
	Configs          []AssignmentExperimentsConfig `json:"configs,omitempty"`
	FlightingVersion int                           `json:"flighting_version,omitempty"`
	ImpressionID     string                        `json:"impression_id,omitempty"`
}

// AssignmentExperimentsConfig holds configuration details for a specific experiment.
type AssignmentExperimentsConfig struct {
	ID         string         `json:"id,omitempty"`
	Parameters map[string]any `json:"parameters,omitempty"`
}

// Package featureflag contains the definition of a segment.
package featureflag

import "time"

// FeatureFlag is the struct that represents a feature flag.
type FeatureFlag struct {
	// Name is the name of the feature flag.
	Name string `json:"name"`

	// BooleanGate is the boolean gate of the feature flag.
	BooleanGate bool `json:"boolean_gate"`

	// PercentageOfActors is the percentage of actors gate of the feature flag.
	// Values will be between 0 and 100.
	PercentageOfActors float64 `json:"percentage_of_actors"`

	// PercentageOfCalls is the percentage of calls gate of the feature flag.
	// Values will be between 0 and 100.
	PercentageOfCalls float64 `json:"percentage_of_calls"`

	// Segments is the list of segment names associated with the feature flag.
	Segments []string `json:"segment_names"`

	// CustomGates is the list of custom gate names set on the feature flag.
	CustomGates []string `json:"custom_gates"`

	// UpdatedAt is the time when the feature flag was last updated in milliseconds since epoch.
	UpdatedAt time.Time `json:"updated_at"`

	// OwningService is the name of the service in Service Catalog for that feature
	OwningService string `json:"owning_service"`
}

// GetFeatureFlagResponse is the response returned by the GetFeatureFlag method.
type GetFeatureFlagResponse struct {
	Name        string
	FeatureFlag *FeatureFlag
	Error       error
}

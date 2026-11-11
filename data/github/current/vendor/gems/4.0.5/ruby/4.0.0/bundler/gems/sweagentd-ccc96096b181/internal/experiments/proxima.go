package experiments

import (
	"context"

	"github.com/github/sweagentd/internal/githubtwirp"
)

// ProximaClient is a passthrough implementation of the Client interface for Proxima.
// Not fully implemented for proxima, but we use this passthrough client to avoid any additional logic.
type ProximaClient struct {
}

var _ Client = &ProximaClient{}

// NewProximaClient creates a new ProximaClient instance.
func NewProximaClient() *ProximaClient {
	return &ProximaClient{}
}

// NewTrafficFiltersDefaults returns empty traffic filters for Proxima.
func (e *ProximaClient) NewTrafficFiltersDefaults(ctx context.Context, twirpClient githubtwirp.ClientInterface, defaultFilters *FilterProps) (TrafficFilters, error) {
	return TrafficFilters{}, nil
}

// GetFeatureAssignment returns nil assignment for Proxima (not implemented).
func (e *ProximaClient) GetFeatureAssignment(ctx context.Context, featureName string, randomizationUnit *TrafficFilter, trafficFilters TrafficFilters) (*Assignment, bool) {
	return nil, false
}
